package NetFPGA::ANNControl;

use strict;
use warnings;

use Carp qw(croak);
use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Path ();
use File::Spec;
use Math::BigInt;

our $VERSION = '0.1';

my $CPU_IMEM_MAX_ADDR = 0x01ff;
my $GPU_IMEM_MAX_ADDR = 0xffff;
my $GPU_DMEM_MAX_ADDR = 0x3fff;

my $ENGINE_CTRL_ENABLE_MASK         = 0x0000_0001;
my $ENGINE_CTRL_COMPACT_RESULT_MASK = 0x0000_0002;
my $ENGINE_CTRL_DEBUG_CLEAR_MASK    = 0x0000_0004;
my $ENGINE_CTRL_OUTPUT_COUNT_MASK   = 0x0000_ff00;
my $ENGINE_CTRL_OUTPUT_BASE_MASK    = 0xffff_0000;

my @REGISTER_LAYOUT = (
  { short => 'sw_d_mem_addr',          symbol => 'USER_TOP_SW_D_MEM_ADDR_REG',        access => 'rw', kind => 'software' },
  { short => 'sw_i_mem_wdata',         symbol => 'USER_TOP_SW_I_MEM_WDATA_REG',       access => 'rw', kind => 'software' },
  { short => 'sw_i_mem_addr',          symbol => 'USER_TOP_SW_I_MEM_ADDR_REG',        access => 'rw', kind => 'software' },
  { short => 'sw_engine_ctrl',         symbol => 'USER_TOP_SW_ENGINE_CTRL_REG',       access => 'rw', kind => 'software' },
  { short => 'sw_gpu_i_mem_wdata',     symbol => 'USER_TOP_SW_GPU_I_MEM_WDATA_REG',   access => 'rw', kind => 'software' },
  { short => 'sw_gpu_i_mem_addr',      symbol => 'USER_TOP_SW_GPU_I_MEM_ADDR_REG',    access => 'rw', kind => 'software' },
  { short => 'sw_gpu_w_mem_wdata_1',   symbol => 'USER_TOP_SW_GPU_W_MEM_WDATA_1_REG', access => 'rw', kind => 'software' },
  { short => 'sw_gpu_w_mem_wdata_0',   symbol => 'USER_TOP_SW_GPU_W_MEM_WDATA_0_REG', access => 'rw', kind => 'software' },
  { short => 'sw_gpu_w_mem_addr',      symbol => 'USER_TOP_SW_GPU_W_MEM_ADDR_REG',    access => 'rw', kind => 'software' },
  { short => 'sw_gpu_ofmap_addr',      symbol => 'USER_TOP_SW_GPU_OFMAP_ADDR_REG',    access => 'rw', kind => 'software' },
  { short => 'hw_engine_status',       symbol => 'USER_TOP_HW_ENGINE_STATUS_REG',     access => 'ro', kind => 'hardware' },
  { short => 'hw_reserved_0',          symbol => 'USER_TOP_HW_RESERVED_0_REG',        access => 'ro', kind => 'hardware' },
  { short => 'hw_reserved_1',          symbol => 'USER_TOP_HW_RESERVED_1_REG',        access => 'ro', kind => 'hardware' },
  { short => 'hw_gpu_ofmap_data_0',    symbol => 'USER_TOP_HW_GPU_OFMAP_DATA_0_REG',  access => 'ro', kind => 'hardware' },
  { short => 'hw_gpu_ofmap_data_1',    symbol => 'USER_TOP_HW_GPU_OFMAP_DATA_1_REG',  access => 'ro', kind => 'hardware' },
  { short => 'hw_dbg_offload_accept_count', symbol => 'USER_TOP_HW_DBG_OFFLOAD_ACCEPT_COUNT_REG', access => 'ro', kind => 'hardware' },
  { short => 'hw_dbg_frame_hold_count', symbol => 'USER_TOP_HW_DBG_FRAME_HOLD_COUNT_REG', access => 'ro', kind => 'hardware' },
  { short => 'hw_dbg_compute_start_count', symbol => 'USER_TOP_HW_DBG_COMPUTE_START_COUNT_REG', access => 'ro', kind => 'hardware' },
  { short => 'hw_dbg_compute_done_count', symbol => 'USER_TOP_HW_DBG_COMPUTE_DONE_COUNT_REG', access => 'ro', kind => 'hardware' },
  { short => 'hw_dbg_result_emit_count', symbol => 'USER_TOP_HW_DBG_RESULT_EMIT_COUNT_REG', access => 'ro', kind => 'hardware' },
  { short => 'hw_dbg_last_parse_request_id', symbol => 'USER_TOP_HW_DBG_LAST_PARSE_REQUEST_ID_REG', access => 'ro', kind => 'hardware' },
  { short => 'hw_dbg_last_compute_request_id', symbol => 'USER_TOP_HW_DBG_LAST_COMPUTE_REQUEST_ID_REG', access => 'ro', kind => 'hardware' },
  { short => 'hw_dbg_last_emit_request_id', symbol => 'USER_TOP_HW_DBG_LAST_EMIT_REQUEST_ID_REG', access => 'ro', kind => 'hardware' },
  { short => 'hw_dbg_flags',          symbol => 'USER_TOP_HW_DBG_FLAGS_REG',          access => 'ro', kind => 'hardware' },
);

my %SHADOW_FILES = (
  cpu_imem  => 'cpu_imem_shadow.txt',
  gpu_imem  => 'gpu_imem_shadow.txt',
  gpu_param => 'gpu_param_shadow.txt',
);

sub new {
  my ($class, %args) = @_;

  my $root_dir = $args{root_dir} || _default_root_dir();
  my $tmp_dir = $ENV{TMPDIR} || '/tmp';
  my $state_dir = $args{state_dir} || $ENV{ANNCTL_STATE_DIR} ||
                  File::Spec->catdir($tmp_dir, 'netfpga_annctl');

  my $self = bless {
    root_dir     => $root_dir,
    state_dir    => $state_dir,
    regread_bin  => $args{regread_bin}  || $ENV{REGREAD_BIN}  || 'regread',
    regwrite_bin => $args{regwrite_bin} || $ENV{REGWRITE_BIN} || 'regwrite',
  }, $class;

  $self->_load_registers();
  return $self;
}

sub root_dir {
  my ($self) = @_;
  return $self->{root_dir};
}

sub state_dir {
  my ($self) = @_;
  return $self->{state_dir};
}

sub register_list {
  my ($self) = @_;
  return @{$self->{register_list}};
}

sub resolve_register {
  my ($self, $target, %opts) = @_;

  defined $target or croak 'missing register target';

  my $normalized = _normalize_name($target);
  if (exists $self->{register_aliases}{$normalized}) {
    return $self->{register_aliases}{$normalized};
  }

  my $addr = eval { $self->_parse_u32($target, allow_bare_hex => 1) };
  if (!$@) {
    if (exists $self->{registers_by_addr}{$addr}) {
      return $self->{registers_by_addr}{$addr};
    }

    croak "unknown register address '$target'" if $opts{require_known};

    return {
      short  => sprintf('0x%08x', $addr),
      symbol => sprintf('0x%08x', $addr),
      access => 'rw',
      kind   => 'numeric',
      addr   => $addr,
    };
  }

  croak "unknown register '$target'";
}

sub reg_read {
  my ($self, $target) = @_;
  my $info = $self->resolve_register($target);
  return $self->_run_regread($info->{addr});
}

sub reg_write {
  my ($self, $target, $value) = @_;

  my $info = $self->resolve_register($target);
  croak "register '$info->{short}' is read-only" if $info->{access} eq 'ro';

  my $u32 = $self->_parse_u32($value, allow_bare_hex => 1);
  $self->_run_regwrite($info->{addr}, $u32);

  return {
    register => $info,
    value    => $u32,
  };
}

sub dump_known_registers {
  my ($self) = @_;
  my @rows;

  for my $info ($self->register_list()) {
    push @rows, {
      %{$info},
      value => $self->_run_regread($info->{addr}),
    };
  }

  return @rows;
}

sub cpu_imem_write {
  my ($self, $addr, $word) = @_;

  my $cpu_addr = $self->_parse_u32($addr, allow_bare_hex => 1);
  my $cpu_word = $self->_parse_u32($word, allow_bare_hex => 1);
  $self->_check_range($cpu_addr, $CPU_IMEM_MAX_ADDR, 'CPU IMEM address');

  # Keep WDATA stable before asserting the write pulse on ADDR[31].
  $self->reg_write('sw_i_mem_wdata', $cpu_word);
  $self->reg_write('sw_i_mem_addr', 0x8000_0000 | $cpu_addr);
  $self->reg_write('sw_i_mem_addr', 0);
  $self->_shadow_write('cpu_imem', $cpu_addr, _format_hex32($cpu_word));

  return {
    addr => $cpu_addr,
    word => $cpu_word,
  };
}

sub cpu_program_load {
  my ($self, $path, %opts) = @_;

  my $base_addr = exists $opts{base_addr} ? $self->_parse_u32($opts{base_addr}, allow_bare_hex => 1) : 0;
  my @entries = $self->_parse_program_entries($path, base_addr => $base_addr, max_addr => $CPU_IMEM_MAX_ADDR);
  my @loaded;

  for my $entry (@entries) {
    push @loaded, $self->cpu_imem_write($entry->{addr}, $entry->{word});
  }

  return @loaded;
}

sub cpu_shadow_read {
  my ($self, $addr) = @_;
  my $cpu_addr = $self->_parse_u32($addr, allow_bare_hex => 1);
  $self->_check_range($cpu_addr, $CPU_IMEM_MAX_ADDR, 'CPU IMEM address');
  return $self->_shadow_read('cpu_imem', $cpu_addr);
}

sub cpu_shadow_dump {
  my ($self, $start, $count) = @_;
  return $self->_shadow_dump('cpu_imem', $start, $count, $CPU_IMEM_MAX_ADDR, 'CPU IMEM address');
}

sub cpu_hw_imem_read {
  my ($self, $addr) = @_;
  my $cpu_addr = $self->_parse_u32($addr, allow_bare_hex => 1);
  $self->_check_range($cpu_addr, $CPU_IMEM_MAX_ADDR, 'CPU IMEM address');

  $self->reg_write('sw_i_mem_addr', 0x4000_0000 | $cpu_addr);
  my $word = $self->reg_read('hw_reserved_0');
  $self->reg_write('sw_i_mem_addr', 0);

  return {
    addr => $cpu_addr,
    word => $word,
  };
}

sub cpu_hw_imem_dump {
  my ($self, $start, $count) = @_;
  my $cpu_start = $self->_parse_u32($start, allow_bare_hex => 1);
  my $cpu_count = $self->_parse_u32($count, allow_bare_hex => 1);
  $cpu_count > 0 or croak 'count must be greater than zero';
  $self->_check_range($cpu_start, $CPU_IMEM_MAX_ADDR, 'CPU IMEM address');
  $self->_check_range($cpu_start + $cpu_count - 1, $CPU_IMEM_MAX_ADDR, 'CPU IMEM address');

  my @rows;
  for my $offset (0 .. $cpu_count - 1) {
    push @rows, $self->cpu_hw_imem_read($cpu_start + $offset);
  }

  return @rows;
}

sub cpu_hw_dmem_read {
  my ($self, $addr) = @_;
  my $cpu_addr = $self->_parse_u32($addr, allow_bare_hex => 1);
  $self->_check_range($cpu_addr, 0x0ff, 'CPU DMEM address');

  $self->reg_write('sw_d_mem_addr', 0x4000_0000 | $cpu_addr);
  my $word = $self->reg_read('hw_reserved_1');
  $self->reg_write('sw_d_mem_addr', 0);

  return {
    addr => $cpu_addr,
    word => $word,
  };
}

sub cpu_hw_dmem_dump {
  my ($self, $start, $count) = @_;
  my $cpu_start = $self->_parse_u32($start, allow_bare_hex => 1);
  my $cpu_count = $self->_parse_u32($count, allow_bare_hex => 1);
  $cpu_count > 0 or croak 'count must be greater than zero';
  $self->_check_range($cpu_start, 0x0ff, 'CPU DMEM address');
  $self->_check_range($cpu_start + $cpu_count - 1, 0x0ff, 'CPU DMEM address');

  my @rows;
  for my $offset (0 .. $cpu_count - 1) {
    push @rows, $self->cpu_hw_dmem_read($cpu_start + $offset);
  }

  return @rows;
}

sub gpu_imem_write {
  my ($self, $addr, $word) = @_;

  my $gpu_addr = $self->_parse_u32($addr, allow_bare_hex => 1);
  my $gpu_word = $self->_parse_u32($word, allow_bare_hex => 1);
  $self->_check_range($gpu_addr, $GPU_IMEM_MAX_ADDR, 'GPU IMEM address');

  # The write pulse is generated from ADDR[31], so write data first.
  $self->reg_write('sw_gpu_i_mem_wdata', $gpu_word);
  $self->reg_write('sw_gpu_i_mem_addr', 0x8000_0000 | $gpu_addr);
  $self->reg_write('sw_gpu_i_mem_addr', 0);
  $self->_shadow_write('gpu_imem', $gpu_addr, _format_hex32($gpu_word));

  return {
    addr => $gpu_addr,
    word => $gpu_word,
  };
}

sub gpu_program_load {
  my ($self, $path, %opts) = @_;

  my $base_addr = exists $opts{base_addr} ? $self->_parse_u32($opts{base_addr}, allow_bare_hex => 1) : 0;
  my @entries = $self->_parse_program_entries($path, base_addr => $base_addr, max_addr => $GPU_IMEM_MAX_ADDR);
  my @loaded;

  for my $entry (@entries) {
    push @loaded, $self->gpu_imem_write($entry->{addr}, $entry->{word});
  }

  return @loaded;
}

sub gpu_imem_shadow_read {
  my ($self, $addr) = @_;
  my $gpu_addr = $self->_parse_u32($addr, allow_bare_hex => 1);
  $self->_check_range($gpu_addr, $GPU_IMEM_MAX_ADDR, 'GPU IMEM address');
  return $self->_shadow_read('gpu_imem', $gpu_addr);
}

sub gpu_imem_shadow_dump {
  my ($self, $start, $count) = @_;
  return $self->_shadow_dump('gpu_imem', $start, $count, $GPU_IMEM_MAX_ADDR, 'GPU IMEM address');
}

sub gpu_param_write {
  my ($self, $addr, @data_tokens) = @_;

  my $gpu_addr = $self->_parse_u32($addr, allow_bare_hex => 1);
  $self->_check_range($gpu_addr, $GPU_DMEM_MAX_ADDR, 'GPU parameter address');

  my ($hi32, $lo32);
  if (@data_tokens == 1) {
    ($hi32, $lo32) = $self->_split_u64($data_tokens[0], allow_bare_hex => 1);
  }
  elsif (@data_tokens == 2) {
    $hi32 = $self->_parse_u32($data_tokens[0], allow_bare_hex => 1);
    $lo32 = $self->_parse_u32($data_tokens[1], allow_bare_hex => 1);
  }
  else {
    croak 'gpu_param_write expects <addr> <data64> or <addr> <hi32> <lo32>';
  }

  # Present HI/LO before asserting the write pulse on ADDR[31].
  $self->reg_write('sw_gpu_w_mem_wdata_1', $hi32);
  $self->reg_write('sw_gpu_w_mem_wdata_0', $lo32);
  $self->reg_write('sw_gpu_w_mem_addr', 0x8000_0000 | $gpu_addr);
  $self->reg_write('sw_gpu_w_mem_addr', 0);
  $self->_shadow_write('gpu_param', $gpu_addr, _format_hex64($hi32, $lo32));

  return {
    addr => $gpu_addr,
    hi32 => $hi32,
    lo32 => $lo32,
  };
}

sub gpu_param_load {
  my ($self, $path) = @_;
  my @entries = $self->_parse_param_entries($path);
  my @loaded;

  for my $entry (@entries) {
    push @loaded, $self->gpu_param_write($entry->{addr}, $entry->{hi32}, $entry->{lo32});
  }

  return @loaded;
}

sub gpu_param_shadow_read {
  my ($self, $addr) = @_;
  my $gpu_addr = $self->_parse_u32($addr, allow_bare_hex => 1);
  $self->_check_range($gpu_addr, $GPU_DMEM_MAX_ADDR, 'GPU parameter address');
  return $self->_shadow_read('gpu_param', $gpu_addr);
}

sub gpu_param_shadow_dump {
  my ($self, $start, $count) = @_;
  return $self->_shadow_dump('gpu_param', $start, $count, $GPU_DMEM_MAX_ADDR, 'GPU parameter address');
}

sub gpu_ofmap_read {
  my ($self, $addr) = @_;
  my $gpu_addr = $self->_parse_u32($addr, allow_bare_hex => 1);
  $self->_check_range($gpu_addr, $GPU_DMEM_MAX_ADDR, 'GPU OFMAP address');

  $self->reg_write('sw_gpu_ofmap_addr', $gpu_addr);
  my $lo32 = $self->reg_read('hw_gpu_ofmap_data_0');
  my $hi32 = $self->reg_read('hw_gpu_ofmap_data_1');

  return {
    addr    => $gpu_addr,
    hi32    => $hi32,
    lo32    => $lo32,
    value64 => _format_hex64($hi32, $lo32),
  };
}

sub gpu_ofmap_dump {
  my ($self, $start, $count) = @_;

  my $gpu_start = $self->_parse_u32($start, allow_bare_hex => 1);
  my $gpu_count = $self->_parse_u32($count, allow_bare_hex => 1);
  $gpu_count > 0 or croak 'count must be greater than zero';
  $self->_check_range($gpu_start, $GPU_DMEM_MAX_ADDR, 'GPU OFMAP address');
  $self->_check_range($gpu_start + $gpu_count - 1, $GPU_DMEM_MAX_ADDR, 'GPU OFMAP address');

  my @rows;
  for my $offset (0 .. $gpu_count - 1) {
    push @rows, $self->gpu_ofmap_read($gpu_start + $offset);
  }

  return @rows;
}

sub engine_status {
  my ($self) = @_;
  my $raw = $self->reg_read('hw_engine_status');
  my $ctrl = $self->reg_read('sw_engine_ctrl');
  return {
    raw                    => $raw,
    sw_engine_ctrl         => $ctrl,
    engine_ready           => ($raw >> 0) & 1,
    cpu_programmed         => ($raw >> 1) & 1,
    gpu_programmed         => ($raw >> 2) & 1,
    param_programmed       => ($raw >> 3) & 1,
    gpu_busy               => ($raw >> 4) & 1,
    compact_result_enable  => ($ctrl & $ENGINE_CTRL_COMPACT_RESULT_MASK) ? 1 : 0,
    output_count           => ($ctrl & $ENGINE_CTRL_OUTPUT_COUNT_MASK) >> 8,
    output_base            => ($ctrl & $ENGINE_CTRL_OUTPUT_BASE_MASK) >> 16,
  };
}

sub engine_enable {
  my ($self, $enable) = @_;
  my $current = $self->reg_read('sw_engine_ctrl');
  my $next = $enable ? ($current | $ENGINE_CTRL_ENABLE_MASK) : ($current & ~$ENGINE_CTRL_ENABLE_MASK);
  $self->reg_write('sw_engine_ctrl', $next);
  return $next;
}

sub engine_result_config {
  my ($self, $base_addr, $count, %opts) = @_;

  my $base = $self->_parse_u32($base_addr, allow_bare_hex => 1);
  my $entries = $self->_parse_u32($count, allow_bare_hex => 1);
  my $compact = exists $opts{compact} ? ($opts{compact} ? 1 : 0) : 1;

  $self->_check_range($base, $GPU_DMEM_MAX_ADDR, 'result output base');
  $entries >= 1 && $entries <= 0xff
    or croak 'result output count must be between 1 and 255';
  $self->_check_range($base + $entries - 1, $GPU_DMEM_MAX_ADDR, 'result output base');

  my $current = $self->reg_read('sw_engine_ctrl');
  my $next = $current;
  $next &= ~($ENGINE_CTRL_COMPACT_RESULT_MASK | $ENGINE_CTRL_OUTPUT_COUNT_MASK | $ENGINE_CTRL_OUTPUT_BASE_MASK);
  $next |= $compact ? $ENGINE_CTRL_COMPACT_RESULT_MASK : 0;
  $next |= (($entries & 0xff) << 8);
  $next |= (($base & 0xffff) << 16);
  $self->reg_write('sw_engine_ctrl', $next);
  return $next;
}

sub engine_result_clear {
  my ($self) = @_;
  my $current = $self->reg_read('sw_engine_ctrl');
  my $next = $current & ~($ENGINE_CTRL_COMPACT_RESULT_MASK | $ENGINE_CTRL_OUTPUT_COUNT_MASK | $ENGINE_CTRL_OUTPUT_BASE_MASK);
  $self->reg_write('sw_engine_ctrl', $next);
  return $next;
}

sub engine_debug_clear {
  my ($self) = @_;
  my $current = $self->reg_read('sw_engine_ctrl');
  my $asserted = $current | $ENGINE_CTRL_DEBUG_CLEAR_MASK;
  my $cleared = $current & ~$ENGINE_CTRL_DEBUG_CLEAR_MASK;
  $self->reg_write('sw_engine_ctrl', $asserted);
  $self->reg_write('sw_engine_ctrl', $cleared);
  return $cleared;
}

sub engine_debug_status {
  my ($self) = @_;
  my $flags = $self->reg_read('hw_dbg_flags');
  return {
    offload_accept_count => $self->reg_read('hw_dbg_offload_accept_count'),
    frame_hold_count     => $self->reg_read('hw_dbg_frame_hold_count'),
    compute_start_count  => $self->reg_read('hw_dbg_compute_start_count'),
    compute_done_count   => $self->reg_read('hw_dbg_compute_done_count'),
    result_emit_count    => $self->reg_read('hw_dbg_result_emit_count'),
    last_parse_request_id => $self->reg_read('hw_dbg_last_parse_request_id') & 0xffff,
    last_compute_request_id => $self->reg_read('hw_dbg_last_compute_request_id') & 0xffff,
    last_emit_request_id => $self->reg_read('hw_dbg_last_emit_request_id') & 0xffff,
    flags_raw            => $flags,
    ingress_overflow_seen => ($flags >> 0) & 1,
    parse_nonfatal_seen  => ($flags >> 1) & 1,
    parse_fatal_seen     => ($flags >> 2) & 1,
    emit_stall_seen      => ($flags >> 3) & 1,
  };
}

sub reset_programming_state {
  my ($self) = @_;

  for my $name (
    qw(
      sw_d_mem_addr
      sw_i_mem_wdata
      sw_i_mem_addr
      sw_engine_ctrl
      sw_gpu_i_mem_wdata
      sw_gpu_i_mem_addr
      sw_gpu_w_mem_wdata_1
      sw_gpu_w_mem_wdata_0
      sw_gpu_w_mem_addr
      sw_gpu_ofmap_addr
    )
  ) {
    $self->reg_write($name, 0);
  }

  $self->_clear_shadow($_) for sort keys %SHADOW_FILES;
  return 1;
}

sub _load_registers {
  my ($self) = @_;

  my @candidate_paths = (
    File::Spec->catfile($self->{root_dir}, 'config', 'reg_defines_v8.h'),
    File::Spec->catfile($self->{root_dir}, 'sw', 'reg_defines_v8.h'),
    File::Spec->catfile($self->{root_dir}, 'config', 'reg_defines_v7.h'),
    File::Spec->catfile($self->{root_dir}, 'sw', 'reg_defines_v7.h'),
    File::Spec->catfile($self->{root_dir}, 'config', 'reg_defines_v5.h'),
    File::Spec->catfile($self->{root_dir}, 'sw', 'reg_defines_v5.h'),
  );
  my ($defines_path) = grep { -e $_ } @candidate_paths;
  my %addr_by_symbol;
  defined $defines_path
    or croak 'missing register defines file ' . join(' or ', @candidate_paths);

  open my $fh, '<', $defines_path or croak "failed to open $defines_path: $!";
  while (my $line = <$fh>) {
    if ($line =~ /^\s*#define\s+(USER_TOP_[A-Z0-9_]+_REG)\s+(0x[0-9a-fA-F]+)/) {
      $addr_by_symbol{$1} = hex($2);
    }
  }
  close $fh or croak "failed to close $defines_path: $!";

  my @registers;
  my %aliases;
  my %by_addr;

  for my $layout (@REGISTER_LAYOUT) {
    exists $addr_by_symbol{$layout->{symbol}}
      or croak "missing register define for $layout->{symbol} in $defines_path";

    my %info = (
      %{$layout},
      addr => $addr_by_symbol{$layout->{symbol}},
    );

    push @registers, \%info;
    $by_addr{$info{addr}} = \%info;

    my $symbol_alias = $info{symbol};
    $symbol_alias =~ s/_REG$//;

    for my $alias (
      $info{short},
      $info{symbol},
      $symbol_alias,
      'user_top_' . $info{short},
    ) {
      $aliases{_normalize_name($alias)} = \%info;
    }
  }

  $self->{register_list}    = \@registers;
  $self->{register_aliases} = \%aliases;
  $self->{registers_by_addr} = \%by_addr;
}

sub _parse_program_entries {
  my ($self, $path, %opts) = @_;
  my $base_addr = $opts{base_addr} || 0;

  open my $fh, '<', $path or croak "failed to open $path: $!";

  my @entries;
  my $next_addr = $base_addr;
  my $line_num = 0;

  while (my $line = <$fh>) {
    $line_num++;
    $line =~ s/\r?\n$//;
    $line =~ s/#.*$//;
    $line =~ s/^\s+//;
    $line =~ s/\s+$//;
    next if $line eq '';

    my @fields = split /\s+/, $line;
    my ($addr, $word);

    if (@fields == 1) {
      $addr = $next_addr;
      $word = $self->_parse_u32($fields[0], hex_default => 1, allow_bare_hex => 1);
    }
    elsif (@fields == 2) {
      $addr = $self->_parse_u32($fields[0], allow_bare_hex => 1);
      $word = $self->_parse_u32($fields[1], hex_default => 1, allow_bare_hex => 1);
    }
    else {
      croak "invalid program entry at $path line $line_num";
    }

    my $max_addr = exists $opts{max_addr} ? $opts{max_addr} : $CPU_IMEM_MAX_ADDR;
    $self->_check_range($addr, $max_addr, 'program address');
    push @entries, {
      addr => $addr,
      word => $word,
    };
    $next_addr = $addr + 1;
  }

  close $fh or croak "failed to close $path: $!";
  return @entries;
}

sub _parse_param_entries {
  my ($self, $path) = @_;

  open my $fh, '<', $path or croak "failed to open $path: $!";

  my @entries;
  my $line_num = 0;

  while (my $line = <$fh>) {
    $line_num++;
    $line =~ s/\r?\n$//;
    $line =~ s/#.*$//;
    $line =~ s/^\s+//;
    $line =~ s/\s+$//;
    next if $line eq '';

    my @fields = split /\s+/, $line;
    my $addr = $self->_parse_u32(shift @fields, allow_bare_hex => 1);
    $self->_check_range($addr, $GPU_DMEM_MAX_ADDR, 'GPU parameter address');

    my ($hi32, $lo32);
    if (@fields == 1) {
      ($hi32, $lo32) = $self->_split_u64($fields[0], hex_default => 1, allow_bare_hex => 1);
    }
    elsif (@fields == 2) {
      $hi32 = $self->_parse_u32($fields[0], hex_default => 1, allow_bare_hex => 1);
      $lo32 = $self->_parse_u32($fields[1], hex_default => 1, allow_bare_hex => 1);
    }
    else {
      croak "invalid parameter entry at $path line $line_num";
    }

    push @entries, {
      addr => $addr,
      hi32 => $hi32,
      lo32 => $lo32,
    };
  }

  close $fh or croak "failed to close $path: $!";
  return @entries;
}

sub _split_u64 {
  my ($self, $value, %opts) = @_;
  my $big = $self->_parse_bigint($value, %opts);
  my $max = Math::BigInt->new('0xffffffffffffffff');

  ($big >= 0 && $big <= $max)
    or croak "value '$value' does not fit in 64 bits";

  my $hex = $big->as_hex();
  $hex =~ s/^0x//i;
  $hex = lc($hex);
  $hex = ('0' x (16 - length($hex))) . $hex if length($hex) < 16;

  my $hi32 = hex(substr($hex, 0, 8));
  my $lo32 = hex(substr($hex, 8, 8));
  return ($hi32, $lo32);
}

sub _parse_u32 {
  my ($self, $value, %opts) = @_;
  my $big = $self->_parse_bigint($value, %opts);
  my $max = Math::BigInt->new('0xffffffff');

  ($big >= 0 && $big <= $max)
    or croak "value '$value' does not fit in 32 bits";

  return int($big->bstr());
}

sub _parse_bigint {
  my ($self, $value, %opts) = @_;
  defined $value or croak 'missing numeric value';

  my $text = $value;
  $text =~ s/_//g;

  if ($text =~ /^0x([0-9a-fA-F]+)$/) {
    return Math::BigInt->new("0x$1");
  }

  if ($opts{hex_default} && $text =~ /^[0-9a-fA-F]+$/) {
    return Math::BigInt->new("0x$text");
  }

  if ($opts{allow_bare_hex} && $text =~ /^[0-9a-fA-F]+$/ && $text =~ /[a-fA-F]/) {
    return Math::BigInt->new("0x$text");
  }

  if ($text =~ /^[0-9]+$/) {
    return Math::BigInt->new($text);
  }

  croak "invalid numeric value '$value'";
}

sub _run_regwrite {
  my ($self, $addr, $value) = @_;
  my @cmd = (
    $self->{regwrite_bin},
    _format_hex32($addr),
    _format_hex32($value),
  );

  system @cmd;
  if ($? != 0) {
    croak sprintf("regwrite failed for %s <= %s", _format_hex32($addr), _format_hex32($value));
  }
}

sub _run_regread {
  my ($self, $addr) = @_;
  my @cmd = ($self->{regread_bin}, _format_hex32($addr));

  open my $fh, '-|', @cmd or croak "failed to start $self->{regread_bin}: $!";
  my @lines = <$fh>;
  close $fh or croak sprintf('regread failed for %s', _format_hex32($addr));

  for my $line (@lines) {
    if ($line =~ /:\s*(0x[0-9a-fA-F]+)\b/) {
      return hex($1);
    }

    if ($line =~ /^\s*(0x[0-9a-fA-F]+)\s*$/) {
      return hex($1);
    }
  }

  croak sprintf('failed to parse regread output for %s', _format_hex32($addr));
}

sub _shadow_write {
  my ($self, $kind, $addr, $value_hex) = @_;
  my %shadow = $self->_load_shadow($kind);
  $shadow{$addr} = $value_hex;
  $self->_save_shadow($kind, \%shadow);
}

sub _shadow_read {
  my ($self, $kind, $addr) = @_;
  my %shadow = $self->_load_shadow($kind);
  exists $shadow{$addr}
    or croak sprintf('no %s shadow entry for %s', $kind, _format_hex32($addr));
  return $shadow{$addr};
}

sub _shadow_dump {
  my ($self, $kind, $start, $count, $max_addr, $label) = @_;

  my $shadow_start = $self->_parse_u32($start, allow_bare_hex => 1);
  my $shadow_count = $self->_parse_u32($count, allow_bare_hex => 1);
  $shadow_count > 0 or croak 'count must be greater than zero';
  $self->_check_range($shadow_start, $max_addr, $label);
  $self->_check_range($shadow_start + $shadow_count - 1, $max_addr, $label);

  my @rows;
  for my $offset (0 .. $shadow_count - 1) {
    my $addr = $shadow_start + $offset;
    push @rows, {
      addr  => $addr,
      value => $self->_shadow_read($kind, $addr),
    };
  }

  return @rows;
}

sub _load_shadow {
  my ($self, $kind) = @_;
  my $path = $self->_shadow_path($kind);
  return () if !-e $path;

  open my $fh, '<', $path or croak "failed to open $path: $!";
  my %shadow;

  while (my $line = <$fh>) {
    $line =~ s/\r?\n$//;
    next if $line =~ /^\s*$/;
    my ($addr_text, $value_text) = split /\s+/, $line, 2;
    defined $value_text or next;
    $shadow{hex($addr_text)} = $value_text;
  }

  close $fh or croak "failed to close $path: $!";
  return %shadow;
}

sub _save_shadow {
  my ($self, $kind, $shadow) = @_;
  $self->_ensure_state_dir();
  my $path = $self->_shadow_path($kind);

  open my $fh, '>', $path or croak "failed to open $path: $!";
  for my $addr (sort { $a <=> $b } keys %{$shadow}) {
    print {$fh} _format_hex32($addr), ' ', $shadow->{$addr}, "\n";
  }
  close $fh or croak "failed to close $path: $!";
}

sub _clear_shadow {
  my ($self, $kind) = @_;
  my $path = $self->_shadow_path($kind);
  unlink $path if -e $path;
}

sub _shadow_path {
  my ($self, $kind) = @_;
  exists $SHADOW_FILES{$kind} or croak "unknown shadow kind '$kind'";
  return File::Spec->catfile($self->{state_dir}, $SHADOW_FILES{$kind});
}

sub _ensure_state_dir {
  my ($self) = @_;
  return if -d $self->{state_dir};
  eval { File::Path::mkpath($self->{state_dir}); 1 }
    or croak "failed to create $self->{state_dir}: $@";
  -d $self->{state_dir}
    or croak "failed to create $self->{state_dir}";
}

sub _check_range {
  my ($self, $value, $max, $label) = @_;
  ($value >= 0 && $value <= $max)
    or croak sprintf('%s out of range: %s', $label, _format_hex32($value));
}

sub _default_root_dir {
  my $module_dir = dirname(abs_path(__FILE__));
  return abs_path(File::Spec->catdir($module_dir, '..', '..'));
}

sub _normalize_name {
  my ($name) = @_;
  $name = lc $name;
  $name =~ s/^\s+//;
  $name =~ s/\s+$//;
  return $name;
}

sub _format_hex32 {
  my ($value) = @_;
  return sprintf('0x%08x', $value & 0xffff_ffff);
}

sub _format_hex64 {
  my ($hi32, $lo32) = @_;
  return sprintf('0x%08x%08x', $hi32 & 0xffff_ffff, $lo32 & 0xffff_ffff);
}

1;
