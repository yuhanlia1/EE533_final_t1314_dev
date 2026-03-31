#!/usr/bin/perl -w
use lib "/usr/local/netfpga/lib/Perl5";
use strict;

my $USER_TOP_SW_CTRL_REG           = 0x02000100;
my $USER_TOP_SW_ICACHE_ADDR_REG    = 0x02000104;
my $USER_TOP_SW_ICACHE_WDATA_REG   = 0x02000108;
my $USER_TOP_SW_BRAM_ADDR_REG      = 0x0200010c;
my $USER_TOP_SW_GPU_MMIO_ADDR_REG  = 0x02000110;
my $USER_TOP_SW_GPU_MMIO_WDATA_REG = 0x02000114;
my $USER_TOP_SW_GPU_IMEM_ADDR_REG  = 0x02000118;
my $USER_TOP_SW_GPU_IMEM_WDATA_REG = 0x0200011c;
my $USER_TOP_HW_STATUS_REG         = 0x02000120;
my $USER_TOP_HW_PC_REG             = 0x02000124;
my $USER_TOP_HW_BRAM_LO_REG        = 0x02000128;
my $USER_TOP_HW_BRAM_HI_REG        = 0x0200012c;
my $USER_TOP_HW_BRAM_CTRL_REG      = 0x02000130;
my $USER_TOP_HW_GPU_MMIO_RDATA_REG = 0x02000134;
my $USER_TOP_HW_GPU_STATUS_REG     = 0x02000138;

my $CTRL_BYPASS_EN   = 1 << 0;
my $CTRL_ICACHE_WR   = 1 << 1;
my $CTRL_BRAM_DBGEN  = 1 << 2;
my $CTRL_SOFT_RESET  = 1 << 3;
my $CTRL_OWNER_GPU   = 1 << 4;
my $CTRL_GPU_MMIO_WR = 1 << 5;
my $CTRL_GPU_MMIO_RD = 1 << 6;
my $CTRL_GPU_IMEM_WR = 1 << 7;

my $GPU_REG_CONTROL    = 0x00;
my $GPU_REG_STATUS     = 0x04;
my $GPU_REG_ENTRY_PC   = 0x08;
my $GPU_REG_TID_INIT   = 0x0C;
my $GPU_REG_WORK_SIZE  = 0x10;
my $GPU_REG_BASE_A_LO  = 0x20;
my $GPU_REG_BASE_A_HI  = 0x24;
my $GPU_REG_BASE_B_LO  = 0x28;
my $GPU_REG_BASE_B_HI  = 0x2C;
my $GPU_REG_BASE_C_LO  = 0x30;
my $GPU_REG_BASE_C_HI  = 0x34;
my $GPU_REG_BASE_D_LO  = 0x38;
my $GPU_REG_BASE_D_HI  = 0x3C;
my $GPU_REG_M          = 0x40;
my $GPU_REG_N          = 0x44;
my $GPU_REG_K          = 0x48;
my $GPU_CTRL_START      = 1 << 0;
my $GPU_CTRL_CLEAR_DONE = 1 << 1;
my $GPU_CTRL_SOFT_RESET = 1 << 2;

my $STATE_FILE = $ENV{"USER_TOP_SWCTRL_STATE_FILE"} || "/tmp/user_top_swctrl_state";

sub parse_u32 {
   my ($s) = @_;
   return 0 unless defined $s;
   return int($s) & 0xFFFFFFFF if $s =~ /^\s*-?\d+\s*$/;
   return hex($s) if $s =~ /^0x/i;
   return hex($s) if $s =~ /[a-fA-F]/;
   return int($s) & 0xFFFFFFFF;
}

sub parse_u64 {
   my ($s) = @_;
   return 0 unless defined $s;
   return int($s) if $s =~ /^\s*-?\d+\s*$/;
   return hex($s) if $s =~ /^0x/i;
   return hex($s) if $s =~ /[a-fA-F]/;
   return int($s);
}

sub fmt_u32 { my ($v)=@_; return sprintf("0x%08x", $v & 0xFFFFFFFF); }
sub fmt_u64 { my ($hi,$lo)=@_; return sprintf("0x%08x%08x", $hi & 0xFFFFFFFF, $lo & 0xFFFFFFFF); }

sub regwrite_u32 {
   my ($addr,$data)=@_;
   my $a=sprintf("0x%08x", $addr & 0xFFFFFFFF);
   my $d=sprintf("0x%08x", $data & 0xFFFFFFFF);
   system("regwrite", $a, $d);
   die "regwrite failed: $a $d\n" if $? != 0;
}

sub regread_u32 {
   my ($addr)=@_;
   my $a=sprintf("0x%08x", $addr & 0xFFFFFFFF);
   my $out=`regread $a`;
   die "regread failed: $a\n" if $? != 0;
   my @hex = ($out =~ /0x([0-9a-fA-F]{8})/g);
   die "could not parse regread output: $out\n" unless @hex;
   return hex($hex[-1]);
}

sub tiny_delay  { select(undef, undef, undef, 0.002); }
sub short_delay { select(undef, undef, undef, 0.010); }

sub ctrl_shadow_read {
   if (-f $STATE_FILE) {
      open(my $fh, '<', $STATE_FILE) or die "cannot open $STATE_FILE\n";
      my $line = <$fh>;
	  close($fh);
	  chomp $line if defined $line;
	  return parse_u32($line);
   }
   return 0;
}

sub ctrl_shadow_write {
   my ($v)=@_;
   open(my $fh, '>', $STATE_FILE) or die "cannot write $STATE_FILE\n";
   printf $fh "0x%08x\n", $v & 0xFFFFFFFF;
   close($fh);
}

sub ctrl_read       { return ctrl_shadow_read(); }
sub ctrl_read_hwraw { return regread_u32($USER_TOP_SW_CTRL_REG); }
sub ctrl_write      { my ($v)=@_; ctrl_shadow_write($v); regwrite_u32($USER_TOP_SW_CTRL_REG, $v); }

sub pulse_ctrl_bit {
   my ($bitmask)=@_;
   my $base = ctrl_read();
   my $hold = $base & (~$bitmask) & 0xFFFFFFFF;
   ctrl_write($hold);
   tiny_delay();
   ctrl_write($hold | $bitmask);
   tiny_delay();
   ctrl_write($hold);
   short_delay();
}

sub soft_reset_pulse {
   ctrl_write($CTRL_SOFT_RESET);
   tiny_delay();
   ctrl_write(0);
   short_delay();
}

sub set_mode_cpu    { my $v = 0; ctrl_write($v);                printf("SW_CTRL = %s  (mode=cpu_process)\n", fmt_u32($v)); }
sub set_mode_gpu    { my $v = $CTRL_OWNER_GPU; ctrl_write($v);  printf("SW_CTRL = %s  (mode=gpu_process)\n", fmt_u32($v)); }
sub set_mode_bypass { my $v = $CTRL_BYPASS_EN; ctrl_write($v);  printf("SW_CTRL = %s  (mode=bypass)\n", fmt_u32($v)); }
sub owner_cpu       { my $v = ctrl_read() & (~$CTRL_OWNER_GPU) & 0xFFFFFFFF; ctrl_write($v); printf("SW_CTRL = %s  (owner=cpu)\n", fmt_u32($v)); }
sub owner_gpu       { my $v = ctrl_read() | $CTRL_OWNER_GPU; ctrl_write($v); printf("SW_CTRL = %s  (owner=gpu)\n", fmt_u32($v)); }
sub bram_dbg_enable { my $v = ctrl_read() | $CTRL_BRAM_DBGEN; ctrl_write($v); printf("SW_CTRL = %s  (bram_dbg=on)\n", fmt_u32($v)); }
sub bram_dbg_disable{ my $v = ctrl_read() & (~$CTRL_BRAM_DBGEN) & 0xFFFFFFFF; ctrl_write($v); printf("SW_CTRL = %s  (bram_dbg=off)\n", fmt_u32($v)); }

sub icache_write_word {
   my ($addr,$inst)=@_;
   regwrite_u32($USER_TOP_SW_ICACHE_ADDR_REG, $addr);
   regwrite_u32($USER_TOP_SW_ICACHE_WDATA_REG, $inst);
   pulse_ctrl_bit($CTRL_ICACHE_WR);
   printf("ICACHE[%u] <= %s\n", $addr & 0xFFFFFFFF, fmt_u32($inst));
}

sub gpu_imem_write_word {
   my ($addr,$inst)=@_;
   regwrite_u32($USER_TOP_SW_GPU_IMEM_ADDR_REG, $addr);
   regwrite_u32($USER_TOP_SW_GPU_IMEM_WDATA_REG, $inst);
   pulse_ctrl_bit($CTRL_GPU_IMEM_WR);
   printf("GPU_IMEM[%u] <= %s\n", $addr & 0xFFFFFFFF, fmt_u32($inst));
}

sub gpu_mmio_write32 {
   my ($addr,$data)=@_;
   regwrite_u32($USER_TOP_SW_GPU_MMIO_ADDR_REG, $addr);
   regwrite_u32($USER_TOP_SW_GPU_MMIO_WDATA_REG, $data);
   pulse_ctrl_bit($CTRL_GPU_MMIO_WR);
   printf("GPU_MMIO[%s] <= %s\n", fmt_u32($addr), fmt_u32($data));
}

sub gpu_mmio_read32 {
   my ($addr)=@_;
   regwrite_u32($USER_TOP_SW_GPU_MMIO_ADDR_REG, $addr);
   pulse_ctrl_bit($CTRL_GPU_MMIO_RD);
   my $v = regread_u32($USER_TOP_HW_GPU_MMIO_RDATA_REG);
   printf("GPU_MMIO[%s] => %s\n", fmt_u32($addr), fmt_u32($v));
   return $v;
}

sub gpu_set_u64_pair {
   my ($lo_addr,$hi_addr,$value)=@_;
   my $lo = $value & 0xFFFFFFFF;
   my $hi = ($value >> 32) & 0xFFFFFFFF;
   gpu_mmio_write32($lo_addr, $lo);
   gpu_mmio_write32($hi_addr, $hi);
}

sub gpu_soft_reset { gpu_mmio_write32($GPU_REG_CONTROL, $GPU_CTRL_SOFT_RESET); }
sub gpu_clear_done { gpu_mmio_write32($GPU_REG_CONTROL, $GPU_CTRL_CLEAR_DONE); }
sub gpu_start      { gpu_mmio_write32($GPU_REG_CONTROL, $GPU_CTRL_START); }

sub decode_state_name {
   my ($s)=@_;
   return "IDLE" if $s == 0;
   return "FILL" if $s == 1;
   return "PROCESS" if $s == 2;
   return "DRAIN" if $s == 3;
   return "UNKNOWN";
}

sub print_ctrl {
   my $v = ctrl_read();
   my $raw = ctrl_read_hwraw();
   printf("SW_CTRL(shadow) = %s\n", fmt_u32($v));
   printf("SW_CTRL(raw)    = %s\n", fmt_u32($raw));
   printf("  bypass_en     : %d\n", ($v >> 0) & 1);
   printf("  icache_wr_bit : %d\n", ($v >> 1) & 1);
   printf("  bram_dbg_en   : %d\n", ($v >> 2) & 1);
   printf("  soft_reset    : %d\n", ($v >> 3) & 1);
   printf("  owner_gpu_cfg : %d\n", ($v >> 4) & 1);
   printf("  gpu_mmio_wr   : %d\n", ($v >> 5) & 1);
   printf("  gpu_mmio_rd   : %d\n", ($v >> 6) & 1);
   printf("  gpu_imem_wr   : %d\n", ($v >> 7) & 1);
}

sub print_status {
   my $v = regread_u32($USER_TOP_HW_STATUS_REG);
   my $fifo_full      = ($v >> 0) & 1;
   my $owner_gpu_live = ($v >> 1) & 1;
   my $pkt_ready      = ($v >> 2) & 1;
   my $proc_active    = ($v >> 3) & 1;
   my $done_sticky    = ($v >> 4) & 1;
   my $bram_rvalid    = ($v >> 5) & 1;
   my $fifo_state     = ($v >> 6) & 0x3;
   my $pkt_len        = ($v >> 8) & 0x1FF;
   printf("HW_STATUS   = %s\n", fmt_u32($v));
   printf("  fifo_full        : %d\n", $fifo_full);
   printf("  owner_gpu_live   : %d\n", $owner_gpu_live);
   printf("  pkt_ready        : %d\n", $pkt_ready);
   printf("  proc_active      : %d\n", $proc_active);
   printf("  done_sticky      : %d\n", $done_sticky);
   printf("  bram_rvalid      : %d\n", $bram_rvalid);
   printf("  fifo_state       : %d (%s)\n", $fifo_state, decode_state_name($fifo_state));
   printf("  pkt_len          : %d\n", $pkt_len);
   if (($v & 0xFFFFFFFF) == 0xDEADBEEF) {
      print "NOTE: HW_STATUS=0xdeadbeef usually means the register address is unmapped or the register block is not responding.\n";
   }
}

sub print_pc {
   my $v = regread_u32($USER_TOP_HW_PC_REG);
   printf("HW_PC       = %s  (%d)\n", fmt_u32($v), $v);
}

sub print_gpu_status {
   my $v = regread_u32($USER_TOP_HW_GPU_STATUS_REG);
   my $busy            = ($v >> 0) & 1;
   my $owner_gpu_live  = ($v >> 1) & 1;
   my $gpu_proc_active = ($v >> 2) & 1;
   my $gpu_proc_done   = ($v >> 3) & 1;
   my $gpu_done_sticky = ($v >> 4) & 1;
   my $gpu_dbg_pc      = ($v >> 10) & 0xFFFF;
   printf("HW_GPU_STATUS = %s\n", fmt_u32($v));
   printf("  gpu_busy        : %d\n", $busy);
   printf("  owner_gpu_live  : %d\n", $owner_gpu_live);
   printf("  gpu_proc_active : %d\n", $gpu_proc_active);
   printf("  gpu_proc_done   : %d\n", $gpu_proc_done);
   printf("  gpu_done_sticky : %d\n", $gpu_done_sticky);
   printf("  gpu_dbg_pc      : %d (0x%04x)\n", $gpu_dbg_pc, $gpu_dbg_pc);
}

sub raw_read  { my ($addr)=@_; my $v=regread_u32($addr); printf("REG[%s] = %s\n", fmt_u32($addr), fmt_u32($v)); }
sub raw_write { my ($addr,$data)=@_; regwrite_u32($addr,$data); printf("REG[%s] <= %s\n", fmt_u32($addr), fmt_u32($data)); }

sub usage {
   print "Usage: $0 <cmd> [args]\n";
   print "  reset | mode_cpu | mode_gpu | mode_bypass | owner_cpu | owner_gpu\n";
   print "  ctrl | status | pc | gpu_status\n";
   print "  icache_write <addr> <inst32>\n";
   print "  gpu_imem_write <addr> <inst32>\n";
   print "  gpu_mmio_write <addr> <data>\n";
   print "  gpu_mmio_read <addr>\n";
   print "  gpu_set_entry <pc> | gpu_set_tid_init <val> | gpu_set_work_size <val>\n";
   print "  gpu_set_base_a <u64> | gpu_set_base_b <u64> | gpu_set_base_c <u64> | gpu_set_base_d <u64>\n";
   print "  gpu_set_m <val> | gpu_set_n <val> | gpu_set_k <val>\n";
   print "  gpu_start | gpu_clear_done | gpu_soft_reset\n";
   print "  raw_read <addr> | raw_write <addr> <data>\n";
}

my $numargs = $#ARGV + 1;
if ($numargs < 1) { usage(); exit(1); }
my $cmd = shift @ARGV;

if    ($cmd eq 'reset')             { soft_reset_pulse(); print "soft reset pulse done\n"; }
elsif ($cmd eq 'mode_cpu')          { set_mode_cpu(); }
elsif ($cmd eq 'mode_gpu')          { set_mode_gpu(); }
elsif ($cmd eq 'mode_bypass')       { set_mode_bypass(); }
elsif ($cmd eq 'owner_cpu')         { owner_cpu(); }
elsif ($cmd eq 'owner_gpu')         { owner_gpu(); }
elsif ($cmd eq 'ctrl')              { print_ctrl(); }
elsif ($cmd eq 'status')            { print_status(); }
elsif ($cmd eq 'pc')                { print_pc(); }
elsif ($cmd eq 'gpu_status')        { print_gpu_status(); }
elsif ($cmd eq 'icache_write')      { @ARGV==2 or die; icache_write_word(parse_u32($ARGV[0]), parse_u32($ARGV[1])); }
elsif ($cmd eq 'gpu_imem_write')    { @ARGV==2 or die; gpu_imem_write_word(parse_u32($ARGV[0]), parse_u32($ARGV[1])); }
elsif ($cmd eq 'gpu_mmio_write')    { @ARGV==2 or die; gpu_mmio_write32(parse_u32($ARGV[0]), parse_u32($ARGV[1])); }
elsif ($cmd eq 'gpu_mmio_read')     { @ARGV==1 or die; gpu_mmio_read32(parse_u32($ARGV[0])); }
elsif ($cmd eq 'gpu_set_entry')     { @ARGV==1 or die; gpu_mmio_write32($GPU_REG_ENTRY_PC, parse_u32($ARGV[0])); }
elsif ($cmd eq 'gpu_set_tid_init')  { @ARGV==1 or die; gpu_mmio_write32($GPU_REG_TID_INIT, parse_u32($ARGV[0])); }
elsif ($cmd eq 'gpu_set_work_size') { @ARGV==1 or die; gpu_mmio_write32($GPU_REG_WORK_SIZE, parse_u32($ARGV[0])); }
elsif ($cmd eq 'gpu_set_base_a')    { @ARGV==1 or die; gpu_set_u64_pair($GPU_REG_BASE_A_LO, $GPU_REG_BASE_A_HI, parse_u64($ARGV[0])); }
elsif ($cmd eq 'gpu_set_base_b')    { @ARGV==1 or die; gpu_set_u64_pair($GPU_REG_BASE_B_LO, $GPU_REG_BASE_B_HI, parse_u64($ARGV[0])); }
elsif ($cmd eq 'gpu_set_base_c')    { @ARGV==1 or die; gpu_set_u64_pair($GPU_REG_BASE_C_LO, $GPU_REG_BASE_C_HI, parse_u64($ARGV[0])); }
elsif ($cmd eq 'gpu_set_base_d')    { @ARGV==1 or die; gpu_set_u64_pair($GPU_REG_BASE_D_LO, $GPU_REG_BASE_D_HI, parse_u64($ARGV[0])); }
elsif ($cmd eq 'gpu_set_m')         { @ARGV==1 or die; gpu_mmio_write32($GPU_REG_M, parse_u32($ARGV[0])); }
elsif ($cmd eq 'gpu_set_n')         { @ARGV==1 or die; gpu_mmio_write32($GPU_REG_N, parse_u32($ARGV[0])); }
elsif ($cmd eq 'gpu_set_k')         { @ARGV==1 or die; gpu_mmio_write32($GPU_REG_K, parse_u32($ARGV[0])); }
elsif ($cmd eq 'gpu_start')         { gpu_start(); }
elsif ($cmd eq 'gpu_clear_done')    { gpu_clear_done(); }
elsif ($cmd eq 'gpu_soft_reset')    { gpu_soft_reset(); }
elsif ($cmd eq 'raw_read')          { @ARGV==1 or die; raw_read(parse_u32($ARGV[0])); }
elsif ($cmd eq 'raw_write')         { @ARGV==2 or die; raw_write(parse_u32($ARGV[0]), parse_u32($ARGV[1])); }
else { usage(); exit(1); }
