import sys
import re

# 辅助函数：循环右移和左移（32位数据）
def ROR(val, r):
    r = r % 32
    return ((val & 0xFFFFFFFF) >> r) | (((val & 0xFFFFFFFF) << (32 - r)) & 0xFFFFFFFF)

def ROL(val, r):
    return ROR(val, 32 - r)

# 对 ARM 数据处理立即数进行编码（用于 add/sub/mov/lsl/cmp 指令）
def encode_immediate(immediate):
    immediate = immediate & 0xFFFFFFFF
    for rotate in range(16):
        shift = rotate * 2
        imm8_candidate = ROL(immediate, shift) & 0xFF
        if ROR(imm8_candidate, shift) == immediate:
            return (rotate, imm8_candidate)
    raise Exception("Immediate value 0x{:X} not encodable in ARM immediate field".format(immediate))

class Instruction:
    def __init__(self, label, mnemonic, operands):
        self.label = label        # 标签，如 "main" 或 ".L6"
        self.mnemonic = mnemonic  # 指令助记符，如 add、sub、mov、lsl、cmp、b、bge、ble、ldr、str 等
        self.operands = operands  # 操作数列表
        self.pc = None            # 程序计数器，稍后赋值

    def is_branch(self):
        # 判断是否为分支指令（例如 b、bge、ble、bx 等）
        return self.mnemonic.lower() in ("b", "bge", "ble") or self.mnemonic.startswith('b')

    def __repr__(self):
        lbl = f"{self.label}: " if self.label else ""
        ops = ", ".join(self.operands) if self.operands else ""
        return f"{lbl}{self.mnemonic} {ops}".strip()

class Compiler:
    def __init__(self, code):
        self.code = code.splitlines()
        self.instructions = []  # 保存所有解析后的指令
        self.labels = {}        # 标签到指令索引（即 PC）的映射

    def tokenize_line(self, line):
        """
        去除行内注释：
          - 如果行以 '#' 开头，则认为整行是注释（但行内出现的 '#' 作为立即数不去掉）
          - 只去除 ';' 后面的部分
        """
        stripped = line.lstrip()
        if stripped.startswith('#'):
            return ""
        line = line.split(';')[0]
        return line.strip()

    def parse(self):
        """
        第一遍扫描：
         - 处理每行，识别出标签和指令
         - 如果行中只有标签，则将标签映射到下一条指令的索引
        """
        label_pattern = re.compile(r'^(?:\.[A-Za-z_]|[A-Za-z_])[A-Za-z0-9_\.]*$')
        for line in self.code:
            line = self.tokenize_line(line)
            if not line:
                continue

            label = None
            if ':' in line:
                parts = line.split(':', 1)
                possible_label = parts[0].strip()
                if label_pattern.match(possible_label):
                    label = possible_label
                    line = parts[1].strip()
            if not line:
                if label is not None:
                    self.labels[label] = len(self.instructions)
                continue

            tokens = re.findall(r'[^\s,]+', line)
            if not tokens:
                continue
            mnemonic = tokens[0]
            operands = tokens[1:] if len(tokens) > 1 else []
            inst = Instruction(label, mnemonic, operands)
            if label:
                self.labels[label] = len(self.instructions)
            self.instructions.append(inst)

    def substitute_aliases(self):
        """
        替换操作数中的寄存器别名为真实的寄存器名，
        例如将 "fp" 替换为 "r11"（包括出现在方括号内的情况）。
        """
        alias_map = {
            "pc": "r15",
            "lr": "r14",
            "sp": "r13",
            "ip": "r12",
            "fp": "r11",   # fp 别名替换为 r11
            "sl": "r10",
            "sb": "r9",
            "v8": "r11",
            "v7": "r10",
            "v6": "r9",
            "v5": "r8",
            "v4": "r7",
            "v3": "r6",
            "v2": "r5",
            "v1": "r4",
            "a4": "r3",
            "a3": "r2",
            "a2": "r1",
            "a1": "r0"
        }
        for inst in self.instructions:
            new_operands = []
            for op in inst.operands:
                new_op = op
                for alias, real_reg in alias_map.items():
                    new_op = re.sub(r'\b' + re.escape(alias) + r'\b', real_reg, new_op)
                new_operands.append(new_op)
            inst.operands = new_operands

    def assign_pc(self):
        for idx, inst in enumerate(self.instructions):
            inst.pc = idx

    def generate_output_file(self, filename="output.txt"):
        """
        将解析后的汇编代码写入输出文件（不输出 PC）。
        文件末尾列出所有标签及其对应的指令索引。
        """
        self.assign_pc()
        try:
            with open(filename, "w") as f:
                for inst in self.instructions:
                    f.write(f"{inst}\n")
                f.write("\nMarks and their corresponding PC values:\n")
                for label, pc in self.labels.items():
                    f.write(f"{label} -> {pc}\n")
            print(f"Output written to {filename}")
        except Exception as e:
            print(f"Error writing to file {filename}: {e}")

    def compile_dp(self, inst):
        """
        编译数据处理指令（包括 add、sub、mov、lsl）的通用函数。
        
        对于 add/sub 格式要求：add/sub Rd, Rn, Operand2
          - 若 Operand2 以 "#" 开头，则为立即数版本；
          - 否则为寄存器操作。
          - 操作码：add -> 0x4，sub -> 0x2
          
        对于 mov/lsl 格式要求：
          - 格式可为：mov/lsl Rd, Operand2
                        或 mov/lsl Rd, Rm, #imm
                        或 mov/lsl Rd, Rm, lsl, #imm
          - 对于 mov/lsl，Rn 固定为 0，操作码固定为 0xD。
          - 若第二操作数以 "#" 开头，则为立即数版本，否则为寄存器版本（可能带移位）。
        """
        mnem = inst.mnemonic.lower()
        cond = 0xE  # 总是执行
        S = 0       # 默认不更新条件标志（注意 cmp 指令单独处理）
        def reg_num(reg):
            if reg.startswith("r"):
                return int(reg[1:])
            else:
                raise Exception("Invalid register format: " + reg)
        
        if mnem in ("add", "sub", "and"):
            if len(inst.operands) != 3:
                raise Exception(f"Invalid number of operands for {mnem} at PC {inst.pc}")
            Rd = reg_num(inst.operands[0])
            Rn = reg_num(inst.operands[1])
            Op2 = inst.operands[2]
            # immediate vs register as before…
            if Op2.startswith("#"):
                immediate_value = int(Op2[1:], 0)
                (rotate, imm8) = encode_immediate(immediate_value)
                I = 1
                operand2 = (rotate << 8) | imm8
            else:
                I = 0
                operand2 = reg_num(Op2)
            # select opcode: ADD=0x4, SUB=0x2, AND=0x0
            if   mnem == "add": opcode = 0x4
            elif mnem == "sub": opcode = 0x2
            else:                opcode = 0x0  # AND
            binary = (
                (cond << 28) | (I << 25) | (opcode << 21) |
                (S << 20)  | (Rn << 16) | (Rd << 12) |
                operand2
            )
            return binary

        elif mnem in ("mov", "lsl"):
            # mov/lsl: Rn 固定为 0，opcode = 0xD
            opcode = 0xD
            Rn = 0
            if len(inst.operands) < 2:
                raise Exception(f"Not enough operands for {mnem} at PC {inst.pc}")
            Rd = reg_num(inst.operands[0])
            if len(inst.operands) == 2:
                # 格式：mov Rd, Operand2
                src = inst.operands[1]
                if src.startswith("#"):
                    immediate_value = int(src[1:], 0)
                    (rotate, imm8) = encode_immediate(immediate_value)
                    I = 1
                    operand2 = (rotate << 8) | imm8
                else:
                    I = 0
                    operand2 = reg_num(src)
            elif len(inst.operands) == 3:
                # 格式：mov Rd, Rm, #imm 或 lsl Rd, Rm, #imm
                Rm = reg_num(inst.operands[1])
                shift_token = inst.operands[2]
                if not shift_token.startswith("#"):
                    raise Exception(f"Expected immediate shift amount at PC {inst.pc}")
                shift_amount = int(shift_token[1:], 0)
                if not (0 <= shift_amount < 32):
                    raise Exception(f"Shift amount out of range at PC {inst.pc}")
                I = 0
                shift_type = 0  # LSL 的类型为 0
                operand2 = (shift_amount << 7) | (shift_type << 5) | Rm
            elif len(inst.operands) == 4:
                # 格式：mov Rd, Rm, lsl, #imm
                Rm = reg_num(inst.operands[1])
                shift_keyword = inst.operands[2].lower()
                if shift_keyword != "lsl":
                    raise Exception(f"Only LSL shift supported at PC {inst.pc}")
                shift_token = inst.operands[3]
                if not shift_token.startswith("#"):
                    raise Exception(f"Expected immediate shift amount at PC {inst.pc}")
                shift_amount = int(shift_token[1:], 0)
                if not (0 <= shift_amount < 32):
                    raise Exception(f"Shift amount out of range at PC {inst.pc}")
                I = 0
                shift_type = 0
                operand2 = (shift_amount << 7) | (shift_type << 5) | Rm
            else:
                raise Exception(f"Invalid number of operands for {mnem} at PC {inst.pc}")
            binary = (cond << 28) | (I << 25) | (opcode << 21) | (S << 20) | (Rn << 16) | (Rd << 12) | operand2
            return binary
        else:
            raise Exception("Unsupported DP instruction: " + inst.mnemonic)

    def compile_dp_instructions(self):
        """
        遍历所有指令，编译其中属于数据处理指令（add, sub, mov, lsl）的指令，
        并以 0xXXXXXXXX 格式输出二进制编码。
        """
        self.assign_pc()
        dp_binaries = []
        for inst in self.instructions:
            if inst.mnemonic.lower() in ("add", "sub", "mov", "lsl", "and"):
                binary = self.compile_dp(inst)
                dp_binaries.append(binary)
                print(f"Compiled {inst.mnemonic.lower()} at PC {inst.pc}: 0x{binary:08X}")
        return dp_binaries

    def compile_cmp(self, inst):
        """
        编译 cmp 指令，支持格式：
           cmp Rn, Operand2
        若 Operand2 以 "#" 开头，则认为是立即数版本；否则为寄存器版本。
        cmp 实际上执行 SUBS，不存储结果，Rd 固定为 0，opcode 固定为 0xA，S 标志置 1。
        """
        if len(inst.operands) != 2:
            raise Exception(f"Invalid number of operands for cmp instruction at PC {inst.pc}")
        def reg_num(reg):
            if reg.startswith("r"):
                return int(reg[1:])
            else:
                raise Exception("Invalid register format: " + reg)
        Rn = reg_num(inst.operands[0])
        Op2 = inst.operands[1]
        if Op2.startswith("#"):
            immediate_value = int(Op2[1:], 0)
            (rotate, imm8) = encode_immediate(immediate_value)
            I = 1
            operand2 = (rotate << 8) | imm8
        else:
            I = 0
            operand2 = reg_num(Op2)
        cond = 0xE       # 条件码 AL
        opcode = 0xA     # cmp 的操作码
        S = 1            # 更新条件标志
        Rd = 0         # cmp 无目标寄存器
        binary = (cond << 28) | (I << 25) | (opcode << 21) | (S << 20) | (Rn << 16) | (Rd << 12) | operand2
        return binary

    def compile_cmp_instructions(self):
        """
        遍历所有指令，编译其中的 cmp 指令，并以 0xXXXXXXXX 格式输出二进制编码。
        """
        self.assign_pc()
        cmp_binaries = []
        for inst in self.instructions:
            if inst.mnemonic.lower() == "cmp":
                binary = self.compile_cmp(inst)
                cmp_binaries.append(binary)
                print(f"Compiled cmp at PC {inst.pc}: 0x{binary:08X}")
        return cmp_binaries

    def compile_branch(self, inst):
        """
        编译分支指令，支持 b, bge, ble 格式：
            b label
            bge label
            ble label
        利用已存储的标签信息计算偏移量：
            offset = target_pc - (inst.pc + 2)
        分支编码格式为：
            cond (4 位) | 101 (3 位) | offset (24 位)
        根据助记符选择条件码：
            b   -> AL (0xE)
            bge -> GE (0xA)
            ble -> LE (0xD)
        """
        if len(inst.operands) != 1:
            raise Exception(f"Invalid number of operands for branch instruction at PC {inst.pc}")
        label = inst.operands[0]
        if label not in self.labels:
            raise Exception(f"Label {label} not found for branch at PC {inst.pc}")
        target_pc = self.labels[label]
        # ARM 中，分支时 PC 为当前指令地址+8字节（即+2条指令，单位4字节）
        offset = target_pc - (inst.pc + 2)
        mnem = inst.mnemonic.lower()
        if mnem == "b":
            cond = 0xE  # AL
        elif mnem == "bge":
            cond = 0xA  # GE
        elif mnem == "ble":
            cond = 0xD  # LE
        else:
            raise Exception(f"Unsupported branch mnemonic: {inst.mnemonic}")
        binary = (cond << 28) | (0x5 << 25) | (offset & 0x00FFFFFF)
        return binary

    def compile_branch_instructions(self):
        """
        遍历所有指令，编译其中的 b, bge, ble 指令，并以 0xXXXXXXXX 格式输出二进制编码。
        """
        self.assign_pc()
        branch_binaries = []
        for inst in self.instructions:
            if inst.mnemonic.lower() in ("b", "bge", "ble"):
                binary = self.compile_branch(inst)
                branch_binaries.append(binary)
                print(f"Compiled {inst.mnemonic.lower()} at PC {inst.pc}: 0x{binary:08X}")
        return branch_binaries

    def parse_memory_operand(self, mem_str):
        """
        解析内存操作数字符串，支持形式如 "[r1, #4]" 或 "[r1]"。
        返回 (base_reg, offset)，其中 offset 为整数（可为负）。
        """
        mem_str = mem_str.replace('[', '').replace(']', '')
        parts = re.split(r'[\s,]+', mem_str.strip())
        if len(parts) == 0:
            raise Exception("Invalid memory operand: " + mem_str)
        base_reg = parts[0]
        offset = 0
        if len(parts) > 1 and parts[1]:
            if parts[1].startswith('#'):
                offset = int(parts[1][1:], 0)
            else:
                offset = int(parts[1], 0)
        return base_reg, offset

    def compile_ldr_str(self, inst):
        """
        编译 ldr/str 指令，支持两种格式：
          1. ldr/str Rd, [Rn, #offset]  —— 常规内存操作数
          2. ldr Rd, .L...             —— literal load，遇到 .L 开头则使用默认常数 128，并转换为 [r8, #128]
        """
        if len(inst.operands) < 2:
            raise Exception(f"Not enough operands for ldr/str at PC {inst.pc}")
        def reg_num(reg):
            if reg.startswith("r"):
                return int(reg[1:])
            else:
                raise Exception("Invalid register format: " + reg)
        Rd = reg_num(inst.operands[0])
        mem_token = inst.operands[1]
        if not mem_token.startswith('['):
            # literal load，要求指令为 ldr
            if inst.mnemonic.lower() != "ldr":
                raise Exception(f"Literal operand not allowed for {inst.mnemonic} at PC {inst.pc}")
            if mem_token.startswith(".L"):
                word_block = 128  # 默认常数
                Rn = 8        # 使用 r8 作为基寄存器
                offset = word_block
                inst.operands[1] = "[r8, #{}]".format(word_block)
            else:
                raise Exception("Invalid literal operand: " + mem_token)
        else:
            mem_operand_str = " ".join(inst.operands[1:])
            base_reg, offset = self.parse_memory_operand(mem_operand_str)
            Rn = reg_num(base_reg)
        if offset >= 0:
            U = 1
            offset_field = offset
        else:
            U = 0
            offset_field = -offset
        if offset_field > 0xFFF:
            raise Exception(f"Offset too large at PC {inst.pc}: {offset}")
        cond = 0xE
        P = 1       # 预索引
        B = 0       # 字访问
        W = 0       # 不写回
        L_bit = 1 if inst.mnemonic.lower() == "ldr" else 0
        binary = (cond << 28) | (0x1 << 26) | (P << 24) | (U << 23) | (B << 22) | (W << 21) | (L_bit << 20) | (Rn << 16) | (Rd << 12) | (offset_field)
        return binary

    def compile_ldr_str_instructions(self):
        self.assign_pc()
        ldstr_binaries = []
        for inst in self.instructions:
            if inst.mnemonic.lower() in ("ldr", "str"):
                binary = self.compile_ldr_str(inst)
                ldstr_binaries.append(binary)
                print(f"Compiled {inst.mnemonic.lower()} at PC {inst.pc}: 0x{binary:08X}")
        return ldstr_binaries

    def compile_all_instructions(self):
        """
        遍历所有指令，根据指令类别调用相应编译函数，返回一个列表，每项为 (PC, binary)。
        列表按 PC 顺序排列。
        """
        self.assign_pc()
        compiled = []
        for inst in self.instructions:
            mnem = inst.mnemonic.lower()
            if mnem in ("add", "sub", "mov", "lsl", "and"):
                binary = self.compile_dp(inst)
            elif mnem == "cmp":
                binary = self.compile_cmp(inst)
            elif mnem in ("b", "bge", "ble"):
                binary = self.compile_branch(inst)
            elif mnem in ("ldr", "str"):
                binary = self.compile_ldr_str(inst)
            else:
                raise Exception(f"Unsupported instruction at PC {inst.pc}: {inst.mnemonic}")
            compiled.append((inst.pc, binary))
        # 按 PC 顺序排序（通常已按顺序）
        compiled.sort(key=lambda x: x[0])
        return compiled

    def compile(self):
        self.parse()
        self.substitute_aliases()
        print("Parsed Instructions:")
        for idx, inst in enumerate(self.instructions):
            branch_flag = " (branch)" if inst.is_branch() else ""
            print(f"PC {idx}: {inst}{branch_flag}")
        print("\nLabel mapping:")
        for label, pc in self.labels.items():
            print(f"{label} -> {pc}")

def main():
    if len(sys.argv) < 2:
        print("Usage: python compiler.py <assembly_file.s>")
        sys.exit(1)
    filename = sys.argv[1]
    try:
        with open(filename, 'r') as f:
            code = f.read()
    except Exception as e:
        print(f"Error reading file {filename}: {e}")
        sys.exit(1)
    compiler = Compiler(code)
    compiler.compile()
    compiler.generate_output_file("output.txt")
    print("\nCompiling all DP instructions (add, sub, mov, lsl):")
    compiler.compile_dp_instructions()
    print("\nCompiling all cmp instructions:")
    compiler.compile_cmp_instructions()
    print("\nCompiling all branch (b, bge, ble) instructions:")
    compiler.compile_branch_instructions()
    print("\nCompiling all 'ldr/str' instructions:")
    compiler.compile_ldr_str_instructions()
    
    # 汇总所有编译好的代码，按照 PC 顺序排列
    compiled_list = compiler.compile_all_instructions()
       
    # 输出二进制代码
    try:
        with open("compiled_binary.txt", "w") as f:
            for _, binary in compiled_list:
                f.write(f"{binary:08X}\n")
        print("\nBinary code has been written to 'compiled_binary.txt'")
    except Exception as e:
        print(f"Error writing binary output: {e}")

if __name__ == "__main__":
    main()
