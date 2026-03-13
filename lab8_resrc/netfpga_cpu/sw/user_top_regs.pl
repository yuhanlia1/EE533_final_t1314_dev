#!/usr/bin/perl -w
use lib "/usr/local/netfpga/lib/Perl5";
use strict;

my $USER_TOP_SW_CTRL_REG         = 0x02000100;
my $USER_TOP_SW_ICACHE_ADDR_REG  = 0x02000104;
my $USER_TOP_SW_ICACHE_WDATA_REG = 0x02000108;
my $USER_TOP_SW_BRAM_ADDR_REG    = 0x0200010c;
my $USER_TOP_HW_STATUS_REG       = 0x02000110;
my $USER_TOP_HW_PC_REG           = 0x02000114;
my $USER_TOP_HW_BRAM_LO_REG      = 0x02000118;
my $USER_TOP_HW_BRAM_HI_REG      = 0x0200011c;
my $USER_TOP_HW_BRAM_CTRL_REG    = 0x02000120;

my $CTRL_BYPASS_EN  = 1 << 0;
my $CTRL_ICACHE_WR  = 1 << 1;
my $CTRL_BRAM_DBGEN = 1 << 2;
my $CTRL_SOFT_RESET = 1 << 3;

sub parse_u32 {
   my ($s) = @_;
   if (!defined $s) { return 0; }
   if ($s =~ /^\s*-?\d+\s*$/) {
      my $v = int($s);
      $v = $v & 0xFFFFFFFF;
      return $v;
   }
   if ($s =~ /^0x/i) { return hex($s); }
   if ($s =~ /[a-fA-F]/) { return hex($s); }
   return int($s);
}

sub fmt_u32 {
   my ($v) = @_;
   return sprintf("0x%08x", $v & 0xFFFFFFFF);
}

sub fmt_u64 {
   my ($hi, $lo) = @_;
   return sprintf("0x%08x%08x", $hi & 0xFFFFFFFF, $lo & 0xFFFFFFFF);
}

sub regwrite_u32 {
   my ($addr, $data) = @_;
   my $a = sprintf("0x%08x", $addr & 0xFFFFFFFF);
   my $d = sprintf("0x%08x", $data & 0xFFFFFFFF);
   system("regwrite", $a, $d);
   if ($? != 0) { die "regwrite failed: $a $d\n"; }
}

sub regread_u32 {
   my ($addr) = @_;
   my $a = sprintf("0x%08x", $addr & 0xFFFFFFFF);
   my $out = `regread $a`;
   if ($? != 0) { die "regread failed: $a\n"; }
   my @hex = ($out =~ /0x([0-9a-fA-F]{8})/g);
   if (@hex >= 1) {
      return hex($hex[-1]);
   }
   die "could not parse regread output: $out\n";
}

sub tiny_delay {
   select(undef, undef, undef, 0.002);
}

sub short_delay {
   select(undef, undef, undef, 0.010);
}

sub ctrl_read {
   return regread_u32($USER_TOP_SW_CTRL_REG);
}

sub ctrl_write {
   my ($v) = @_;
   regwrite_u32($USER_TOP_SW_CTRL_REG, $v);
}

sub ctrl_set_bits {
   my ($mask) = @_;
   my $v = ctrl_read();
   $v |= $mask;
   ctrl_write($v);
   return $v;
}

sub ctrl_clr_bits {
   my ($mask) = @_;
   my $v = ctrl_read();
   $v &= (~$mask) & 0xFFFFFFFF;
   ctrl_write($v);
   return $v;
}

sub soft_reset_pulse {
   ctrl_set_bits($CTRL_SOFT_RESET);
   tiny_delay();
   ctrl_clr_bits($CTRL_SOFT_RESET);
   short_delay();
}

sub set_mode_cpu {
   my $v = ctrl_clr_bits($CTRL_BYPASS_EN);
   printf("SW_CTRL = %s  (mode=cpu_process)\n", fmt_u32($v));
}

sub set_mode_bypass {
   my $v = ctrl_set_bits($CTRL_BYPASS_EN);
   printf("SW_CTRL = %s  (mode=bypass)\n", fmt_u32($v));
}

sub bram_dbg_enable {
   my $v = ctrl_set_bits($CTRL_BRAM_DBGEN);
   printf("SW_CTRL = %s  (bram_dbg=on)\n", fmt_u32($v));
}

sub bram_dbg_disable {
   my $v = ctrl_clr_bits($CTRL_BRAM_DBGEN);
   printf("SW_CTRL = %s  (bram_dbg=off)\n", fmt_u32($v));
}

sub icache_write_word {
   my ($addr, $inst) = @_;
   my $base = ctrl_read();
   my $hold = $base & (~$CTRL_ICACHE_WR) & 0xFFFFFFFF;
   regwrite_u32($USER_TOP_SW_ICACHE_ADDR_REG,  $addr);
   regwrite_u32($USER_TOP_SW_ICACHE_WDATA_REG, $inst);
   ctrl_write($hold);
   tiny_delay();
   ctrl_write($hold | $CTRL_ICACHE_WR);
   tiny_delay();
   ctrl_write($hold);
   short_delay();
}

sub status_read_raw {
   return regread_u32($USER_TOP_HW_STATUS_REG);
}

sub pc_read_raw {
   return regread_u32($USER_TOP_HW_PC_REG);
}

sub decode_state_name {
   my ($s) = @_;
   return "IDLE"    if $s == 0;
   return "FILL"    if $s == 1;
   return "PROCESS" if $s == 2;
   return "DRAIN"   if $s == 3;
   return "UNKNOWN";
}

sub print_status {
   my $v = status_read_raw();
   my $fifo_full   = ($v >> 0) & 1;
   my $pkt_ready   = ($v >> 1) & 1;
   my $cpu_active  = ($v >> 2) & 1;
   my $cpu_done    = ($v >> 3) & 1;
   my $bram_rvalid = ($v >> 4) & 1;
   my $fifo_state  = ($v >> 5) & 0x3;
   my $pkt_len     = ($v >> 7) & 0x1FF;
   printf("HW_STATUS   = %s\n", fmt_u32($v));
   printf("  fifo_full   : %d\n", $fifo_full);
   printf("  pkt_ready   : %d\n", $pkt_ready);
   printf("  cpu_active  : %d\n", $cpu_active);
   printf("  cpu_done    : %d\n", $cpu_done);
   printf("  bram_rvalid : %d\n", $bram_rvalid);
   printf("  fifo_state  : %d (%s)\n", $fifo_state, decode_state_name($fifo_state));
   printf("  pkt_len     : %d\n", $pkt_len);
}

sub print_pc {
   my $v = pc_read_raw();
   printf("HW_PC       = %s  (%d)\n", fmt_u32($v), $v);
}

sub bram_read_word {
   my ($addr) = @_;
   my $ctrl0 = ctrl_read();
   my $ctrl1 = $ctrl0 | $CTRL_BRAM_DBGEN;
   ctrl_write($ctrl1);
   regwrite_u32($USER_TOP_SW_BRAM_ADDR_REG, $addr);
   short_delay();
   my $status = status_read_raw();
   my $rvalid = ($status >> 4) & 1;
   my $lo   = regread_u32($USER_TOP_HW_BRAM_LO_REG);
   my $hi   = regread_u32($USER_TOP_HW_BRAM_HI_REG);
   my $ctrl = regread_u32($USER_TOP_HW_BRAM_CTRL_REG);
   return ($lo, $hi, $ctrl, $rvalid);
}

sub bram_dump_range {
   my ($start, $count) = @_;
   my $k;
   for ($k = 0; $k < $count; $k = $k + 1) {
      my $addr = ($start + $k) & 0xFFFFFFFF;
      my ($lo, $hi, $ctrl, $rvalid) = bram_read_word($addr);
      printf("BRAM[%d]  data=%s ctrl=%s rvalid=%d\n", $addr, fmt_u64($hi, $lo), fmt_u32($ctrl), $rvalid);
   }
}

sub dump_allregs {
   my $sw_ctrl         = regread_u32($USER_TOP_SW_CTRL_REG);
   my $sw_icache_addr  = regread_u32($USER_TOP_SW_ICACHE_ADDR_REG);
   my $sw_icache_wdata = regread_u32($USER_TOP_SW_ICACHE_WDATA_REG);
   my $sw_bram_addr    = regread_u32($USER_TOP_SW_BRAM_ADDR_REG);
   my $hw_status       = regread_u32($USER_TOP_HW_STATUS_REG);
   my $hw_pc           = regread_u32($USER_TOP_HW_PC_REG);
   my $hw_bram_lo      = regread_u32($USER_TOP_HW_BRAM_LO_REG);
   my $hw_bram_hi      = regread_u32($USER_TOP_HW_BRAM_HI_REG);
   my $hw_bram_ctrl    = regread_u32($USER_TOP_HW_BRAM_CTRL_REG);

   print "\n[SW regs]\n";
   printf("  SW_CTRL         = %s\n", fmt_u32($sw_ctrl));
   printf("  SW_ICACHE_ADDR  = %s\n", fmt_u32($sw_icache_addr));
   printf("  SW_ICACHE_WDATA = %s\n", fmt_u32($sw_icache_wdata));
   printf("  SW_BRAM_ADDR    = %s\n", fmt_u32($sw_bram_addr));

   print "\n[HW regs]\n";
   printf("  HW_STATUS       = %s\n", fmt_u32($hw_status));
   printf("  HW_PC           = %s\n", fmt_u32($hw_pc));
   printf("  HW_BRAM_LO      = %s\n", fmt_u32($hw_bram_lo));
   printf("  HW_BRAM_HI      = %s\n", fmt_u32($hw_bram_hi));
   printf("  HW_BRAM_CTRL    = %s\n", fmt_u32($hw_bram_ctrl));
   print "\n";
}

sub raw_read {
   my ($addr) = @_;
   my $v = regread_u32($addr);
   printf("REG[%s] = %s\n", fmt_u32($addr), fmt_u32($v));
}

sub raw_write {
   my ($addr, $data) = @_;
   regwrite_u32($addr, $data);
   printf("REG[%s] <= %s\n", fmt_u32($addr), fmt_u32($data));
}

sub usage {
   print "Usage: $0 <cmd> [args]\n";
   print "  reset\n";
   print "  mode_cpu\n";
   print "  mode_bypass\n";
   print "  bram_dbg_on\n";
   print "  bram_dbg_off\n";
   print "  ctrl\n";
   print "  status\n";
   print "  pc\n";
   print "  icache_write <addr> <inst32>\n";
   print "  bram_read <addr>\n";
   print "  bram_dump <start> <count>\n";
   print "  allregs\n";
   print "  raw_read  <addr>\n";
   print "  raw_write <addr> <data>\n";
}

my $numargs = $#ARGV + 1;
if ($numargs < 1) { usage(); exit(1); }

my $cmd = $ARGV[0];

if ($cmd eq "reset") {
   soft_reset_pulse();
   print "soft reset pulse sent\n";

} elsif ($cmd eq "mode_cpu") {
   set_mode_cpu();

} elsif ($cmd eq "mode_bypass") {
   set_mode_bypass();

} elsif ($cmd eq "bram_dbg_on") {
   bram_dbg_enable();

} elsif ($cmd eq "bram_dbg_off") {
   bram_dbg_disable();

} elsif ($cmd eq "ctrl") {
   my $v = ctrl_read();
   printf("SW_CTRL     = %s\n", fmt_u32($v));
   printf("  bypass_enable : %d\n", ($v & $CTRL_BYPASS_EN)  ? 1 : 0);
   printf("  icache_wr_req : %d\n", ($v & $CTRL_ICACHE_WR)  ? 1 : 0);
   printf("  dbg_bram_en   : %d\n", ($v & $CTRL_BRAM_DBGEN) ? 1 : 0);
   printf("  soft_reset    : %d\n", ($v & $CTRL_SOFT_RESET) ? 1 : 0);

} elsif ($cmd eq "status") {
   print_status();

} elsif ($cmd eq "pc") {
   print_pc();

} elsif ($cmd eq "icache_write") {
   if ($numargs < 3) { usage(); exit(1); }
   my $addr = parse_u32($ARGV[1]);
   my $inst = parse_u32($ARGV[2]);
   icache_write_word($addr, $inst);
   printf("ICACHE[%d] <= %s\n", $addr, fmt_u32($inst));

} elsif ($cmd eq "bram_read") {
   if ($numargs < 2) { usage(); exit(1); }
   my $addr = parse_u32($ARGV[1]);
   my ($lo, $hi, $ctrl, $rvalid) = bram_read_word($addr);
   printf("BRAM[%d]  data=%s ctrl=%s rvalid=%d\n", $addr, fmt_u64($hi, $lo), fmt_u32($ctrl), $rvalid);

} elsif ($cmd eq "bram_dump") {
   if ($numargs < 3) { usage(); exit(1); }
   my $start = parse_u32($ARGV[1]);
   my $count = parse_u32($ARGV[2]);
   bram_dump_range($start, $count);

} elsif ($cmd eq "allregs") {
   dump_allregs();

} elsif ($cmd eq "raw_read") {
   if ($numargs < 2) { usage(); exit(1); }
   my $addr = parse_u32($ARGV[1]);
   raw_read($addr);

} elsif ($cmd eq "raw_write") {
   if ($numargs < 3) { usage(); exit(1); }
   my $addr = parse_u32($ARGV[1]);
   my $data = parse_u32($ARGV[2]);
   raw_write($addr, $data);

} else {
   print "Unrecognized command $cmd\n";
   usage();
   exit(1);
}
