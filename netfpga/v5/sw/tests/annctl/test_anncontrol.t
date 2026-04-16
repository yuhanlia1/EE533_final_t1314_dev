#!/usr/bin/perl

use strict;
use warnings;

use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin qw($Bin);
use Test::More;

use lib File::Spec->catdir($Bin, '..', '..', 'lib');

use NetFPGA::ANNControl;

my $ROOT_DIR = File::Spec->rel2abs(File::Spec->catdir($Bin, '..', '..', '..'));
my $ANNCTL   = File::Spec->catfile($ROOT_DIR, 'sw', 'annctl');
my $DEFINES  = File::Spec->catfile($ROOT_DIR, 'sw', 'reg_defines_v5.h');

my %ADDR = (
  sw_d_mem_addr        => 0x02000100,
  sw_i_mem_wdata       => 0x02000104,
  sw_i_mem_addr        => 0x02000108,
  sw_engine_ctrl       => 0x0200010c,
  sw_gpu_i_mem_wdata   => 0x02000110,
  sw_gpu_i_mem_addr    => 0x02000114,
  sw_gpu_w_mem_wdata_1 => 0x02000118,
  sw_gpu_w_mem_wdata_0 => 0x0200011c,
  sw_gpu_w_mem_addr    => 0x02000120,
  sw_gpu_ofmap_addr    => 0x02000124,
  hw_engine_status     => 0x02000128,
  hw_reserved_0        => 0x0200012c,
  hw_reserved_1        => 0x02000130,
  hw_gpu_ofmap_data_0  => 0x02000134,
  hw_gpu_ofmap_data_1  => 0x02000138,
);

sub slurp {
  my ($path) = @_;
  open my $fh, '<', $path or die "failed to open $path: $!";
  local $/;
  my $text = <$fh>;
  close $fh or die "failed to close $path: $!";
  return $text;
}

sub write_text {
  my ($path, $content) = @_;
  open my $fh, '>', $path or die "failed to open $path: $!";
  print {$fh} $content;
  close $fh or die "failed to close $path: $!";
}

sub make_mock_env {
  my $dir = tempdir(CLEANUP => 1);
  my $mock_bin = File::Spec->catdir($dir, 'mock_bin');
  my $state_dir = File::Spec->catdir($dir, 'annctl_state');
  my $state_path = File::Spec->catfile($dir, 'state.json');
  my $log_path = File::Spec->catfile($dir, 'regwrite.log');
  make_path($mock_bin, $state_dir);
  write_text($log_path, '');

  my $state_json = <<"EOF_STATE";
{
  "registers": {
    "0x02000100": 0,
    "0x02000104": 0,
    "0x02000108": 0,
    "0x0200010c": 0,
    "0x02000110": 0,
    "0x02000114": 0,
    "0x02000118": 0,
    "0x0200011c": 0,
    "0x02000120": 0,
    "0x02000124": 0,
    "0x02000128": 31,
    "0x0200012c": 0,
    "0x02000130": 0,
    "0x02000134": 1432778632,
    "0x02000138": 287454020
  },
  "meta": {
    "sw_d_mem_addr": 33554688,
    "sw_i_mem_wdata": 33554692,
    "sw_i_mem_addr": 33554696,
    "sw_gpu_ofmap_addr": 33554724,
    "hw_reserved_0": 33554732,
    "hw_reserved_1": 33554736,
    "hw_gpu_ofmap_data_0": 33554740,
    "hw_gpu_ofmap_data_1": 33554744
  },
  "cpu_imem": {},
  "cpu_dmem": {
    "0": "0x000000a5",
    "1": "0x0000005a",
    "2": "0x0000003c"
  },
  "ofmap": {
    "0": "0x1122334455667788",
    "1": "0xdeadbeefcafef00d"
  }
}
EOF_STATE
  write_text($state_path, $state_json);

  my $regwrite_path = File::Spec->catfile($mock_bin, 'regwrite.py');
  write_text($regwrite_path, <<"EOF_REGWRITE");
#!/usr/bin/env python3
import json

state_path = r"$state_path"
log_path = r"$log_path"

with open(state_path, "r", encoding="utf-8") as fh:
    state = json.load(fh)

import sys
if len(sys.argv) != 3:
    raise SystemExit("usage: regwrite <addr> <value>")

addr = int(sys.argv[1], 16)
value = int(sys.argv[2], 16)

registers = state["registers"]
registers[f"0x{addr:08x}"] = value
meta = state["meta"]

if addr == meta["sw_i_mem_addr"]:
    cpu_addr = value & 0x1FF
    if value & 0x80000000:
        wdata = registers[f"0x{meta['sw_i_mem_wdata']:08x}"]
        state["cpu_imem"][str(cpu_addr)] = f"0x{wdata:08x}"
    elif value & 0x40000000:
        word_hex = state["cpu_imem"].get(str(cpu_addr), "0x00000000")
        registers[f"0x{meta['hw_reserved_0']:08x}"] = int(word_hex, 16)

if addr == meta["sw_d_mem_addr"] and (value & 0x40000000):
    cpu_addr = value & 0x0FF
    word_hex = state["cpu_dmem"].get(str(cpu_addr), "0x00000000")
    registers[f"0x{meta['hw_reserved_1']:08x}"] = int(word_hex, 16)

if addr == meta["sw_gpu_ofmap_addr"]:
    word_hex = state["ofmap"].get(str(value), "0x0000000000000000")
    word = int(word_hex, 16)
    registers[f"0x{meta['hw_gpu_ofmap_data_0']:08x}"] = word & 0xFFFFFFFF
    registers[f"0x{meta['hw_gpu_ofmap_data_1']:08x}"] = (word >> 32) & 0xFFFFFFFF

with open(state_path, "w", encoding="utf-8") as fh:
    json.dump(state, fh, indent=2, sort_keys=True)

with open(log_path, "a", encoding="utf-8") as fh:
    fh.write(f"WRITE 0x{addr:08x} 0x{value:08x}\\n")
EOF_REGWRITE

  my $regread_path = File::Spec->catfile($mock_bin, 'regread.py');
  write_text($regread_path, <<"EOF_REGREAD");
#!/usr/bin/env python3
import json
import sys

state_path = r"$state_path"

if len(sys.argv) != 2:
    raise SystemExit("usage: regread <addr>")

addr = int(sys.argv[1], 16)
with open(state_path, "r", encoding="utf-8") as fh:
    state = json.load(fh)

value = state["registers"].get(f"0x{addr:08x}", 0)
print(f"Reg 0x{addr:08x} ({addr}): 0x{value:08x}")
EOF_REGREAD

  chmod 0755, $regwrite_path or die "chmod failed for $regwrite_path: $!";
  chmod 0755, $regread_path or die "chmod failed for $regread_path: $!";

  return {
    dir         => $dir,
    state_dir   => $state_dir,
    log_path    => $log_path,
    regread_bin => $regread_path,
    regwrite_bin => $regwrite_path,
  };
}

sub new_ctl {
  my ($env, %extra) = @_;
  return NetFPGA::ANNControl->new(
    root_dir     => $extra{root_dir} || $ROOT_DIR,
    state_dir    => $extra{state_dir} || $env->{state_dir},
    regread_bin  => $env->{regread_bin},
    regwrite_bin => $env->{regwrite_bin},
  );
}

sub run_annctl {
  my ($env, @args) = @_;
  local $ENV{ANNCTL_STATE_DIR} = $env->{state_dir};
  local $ENV{REGREAD_BIN} = $env->{regread_bin};
  local $ENV{REGWRITE_BIN} = $env->{regwrite_bin};

  open my $fh, '-|', $^X, $ANNCTL, @args or die "failed to run $ANNCTL: $!";
  my @lines = <$fh>;
  close $fh or die "annctl failed";
  return join('', @lines);
}

my $env = make_mock_env();
my $ctl = new_ctl($env);

is($ctl->resolve_register('sw_engine_ctrl')->{addr}, $ADDR{sw_engine_ctrl}, 'short register name resolves to current address');
is($ctl->resolve_register('USER_TOP_SW_ENGINE_CTRL')->{addr}, $ADDR{sw_engine_ctrl}, 'symbol alias resolves to current address');
is($ctl->resolve_register('0x0200010c')->{short}, 'sw_engine_ctrl', 'numeric register address resolves to known register');

eval { $ctl->reg_write('hw_engine_status', 1) };
like($@, qr/read-only/, 'read-only register writes are rejected');

write_text($env->{log_path}, '');
$ctl->cpu_imem_write(1, '0x12345678');
is(
  slurp($env->{log_path}),
  "WRITE 0x02000104 0x12345678\nWRITE 0x02000108 0x80000001\nWRITE 0x02000108 0x00000000\n",
  'cpu_imem_write preserves WDATA-before-ADDR pulse ordering',
);
is($ctl->cpu_shadow_read(1), '0x12345678', 'CPU IMEM shadow stores the written word');

my $cpu_hw_row = $ctl->cpu_hw_imem_read(1);
is($cpu_hw_row->{word}, 0x12345678, 'CPU IMEM hardware readback returns the last written word');

write_text($env->{log_path}, '');
my $gpu_param_result = $ctl->gpu_param_write(3, '0x0000000a0000000b');
is($gpu_param_result->{hi32}, 0x0000000a, 'gpu_param_write splits HI32 correctly');
is($gpu_param_result->{lo32}, 0x0000000b, 'gpu_param_write splits LO32 correctly');
is(
  slurp($env->{log_path}),
  "WRITE 0x02000118 0x0000000a\nWRITE 0x0200011c 0x0000000b\nWRITE 0x02000120 0x80000003\nWRITE 0x02000120 0x00000000\n",
  'gpu_param_write writes HI/LO before pulsing the address register',
);
is($ctl->gpu_param_shadow_read(3), '0x0000000a0000000b', 'GPU parameter shadow stores 64-bit words');

my $status = $ctl->engine_status();
is($status->{raw}, 0x0000001f, 'engine_status returns the raw register value');
is($status->{gpu_busy}, 1, 'engine_status decodes gpu_busy');
is($status->{param_programmed}, 1, 'engine_status decodes param_programmed');

my $ofmap_row = $ctl->gpu_ofmap_read(1);
is($ofmap_row->{value64}, '0xdeadbeefcafef00d', 'gpu_ofmap_read assembles 64-bit output values');

my ($program_fd, $program_path);
$program_path = File::Spec->catfile($env->{dir}, 'program.txt');
write_text($program_path, "# comment\nDEADBEEF\n0x00000005 0xCAFEBABE\n");
my @program_entries = $ctl->_parse_program_entries($program_path, base_addr => 2);
is_deeply(
  \@program_entries,
  [
    { addr => 2, word => 0xDEADBEEF },
    { addr => 5, word => 0xCAFEBABE },
  ],
  '_parse_program_entries handles sequential and explicit addresses',
);

my $params_path = File::Spec->catfile($env->{dir}, 'params.txt');
write_text($params_path, "0x3 0x0000000100000002\n0x4 0x0000000a 0x0000000b\n");
my @param_entries = $ctl->_parse_param_entries($params_path);
is_deeply(
  \@param_entries,
  [
    { addr => 3, hi32 => 0x00000001, lo32 => 0x00000002 },
    { addr => 4, hi32 => 0x0000000a, lo32 => 0x0000000b },
  ],
  '_parse_param_entries supports 64-bit and split HI/LO parameter lines',
);

$ctl->reset_programming_state();
eval { $ctl->cpu_shadow_read(1) };
like($@, qr/no cpu_imem shadow entry/, 'reset_programming_state clears CPU shadow state');

my $status_output = run_annctl($env, 'engine', 'status');
like($status_output, qr/raw\s+= 0x0000001f/, 'annctl engine status CLI smoke succeeds');

$ctl->cpu_imem_write(1, '0x12345678');
my $cpu_cli_output = run_annctl($env, 'cpu', 'hw-imem-read', '1');
like($cpu_cli_output, qr/cpu_hw_imem\[0x00000001\] = 0x12345678/, 'annctl cpu hw-imem-read CLI smoke succeeds');

my $ofmap_cli_output = run_annctl($env, 'gpu', 'ofmap-read', '1');
like($ofmap_cli_output, qr/gpu_ofmap\[0x00000001\] = 0xdeadbeefcafef00d/, 'annctl gpu ofmap-read CLI smoke succeeds');

my $temp_root = tempdir(CLEANUP => 1);
make_path(File::Spec->catdir($temp_root, 'sw'));
copy(
  $DEFINES,
  File::Spec->catfile($temp_root, 'sw', 'reg_defines_v5.h'),
) or die "failed to copy reg_defines_v5.h: $!";

my $temp_ctl = new_ctl($env, root_dir => $temp_root, state_dir => File::Spec->catdir($temp_root, 'state'));
is($temp_ctl->resolve_register('sw_gpu_ofmap_addr')->{addr}, $ADDR{sw_gpu_ofmap_addr}, 'register map loads from sw/reg_defines_v5.h under the selected root');

my $missing_root = tempdir(CLEANUP => 1);
eval { new_ctl($env, root_dir => $missing_root, state_dir => File::Spec->catdir($missing_root, 'state')) };
like($@, qr/missing register defines file .*sw\/reg_defines_v5\.h/, 'constructor fails clearly when sw/reg_defines_v5.h is absent');

done_testing();
