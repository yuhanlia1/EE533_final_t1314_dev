IVERILOG ?= iverilog
VVP ?= vvp

BUILD_DIR := build
ROOT_DIR := ..
TOPS := user_top_tb user_pre_debug_tb

DEFINES ?= -DUDP_REG_ADDR_WIDTH=16 -DCPCI_NF2_DATA_WIDTH=32 -DNO_VCD
IVERILOG_FLAGS ?= -g2012 -Wall $(DEFINES)

COMMON_SRC := \
	../../src/tb_necessary/generic_regs_sim_stub.v \

USER_TOP_SRC := \
	$(ROOT_DIR)/src/fifo_bram.v \
	$(ROOT_DIR)/src/convertible_fifo.v \
	$(ROOT_DIR)/src/packet_action_selector.v \
	$(ROOT_DIR)/src/user_top.v \
	user_top_tb.v

USER_PRE_DEBUG_SRC := \
	$(COMMON_SRC) \
	$(ROOT_DIR)/src/user_pre_debug.v \
	user_pre_debug_tb.v

.PHONY: all run wave clean

all: run

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/user_top_tb.vvp: $(COMMON_SRC) $(USER_TOP_SRC) | $(BUILD_DIR)
	$(IVERILOG) $(IVERILOG_FLAGS) -o $@ $(COMMON_SRC) $(USER_TOP_SRC)

$(BUILD_DIR)/user_pre_debug_tb.vvp: $(USER_PRE_DEBUG_SRC) | $(BUILD_DIR)
	$(IVERILOG) $(IVERILOG_FLAGS) -o $@ $(USER_PRE_DEBUG_SRC)

run: $(BUILD_DIR)/user_top_tb.vvp $(BUILD_DIR)/user_pre_debug_tb.vvp
	$(VVP) $(BUILD_DIR)/user_top_tb.vvp
	$(VVP) $(BUILD_DIR)/user_pre_debug_tb.vvp

wave: run
	@printf 'Waveforms written under %s/*.vcd\n' "$(BUILD_DIR)"

clean:
	rm -rf $(BUILD_DIR)
