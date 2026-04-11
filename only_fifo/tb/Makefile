IVERILOG ?= iverilog
VVP ?= vvp

TOP := user_top_tb
BUILD_DIR := build

DEFINES ?= -DUDP_REG_ADDR_WIDTH=16 -DCPCI_NF2_DATA_WIDTH=32
IVERILOG_FLAGS ?= -g2012 -Wall $(DEFINES)

SRC := \
	../src/fifo_bram.v \
	../src/convertible_fifo.v \
	../src/packet_action_selector.v \
	../src/user_top.v \
	user_top_tb.v

.PHONY: all run wave clean

all: run

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/$(TOP).vvp: $(SRC) | $(BUILD_DIR)
	$(IVERILOG) $(IVERILOG_FLAGS) -o $@ $(SRC)

run: $(BUILD_DIR)/$(TOP).vvp
	$(VVP) $<

wave: run
	@printf 'Waveform written to %s/%s.vcd\n' "$(BUILD_DIR)" "$(TOP)"

clean:
	rm -rf $(BUILD_DIR)
