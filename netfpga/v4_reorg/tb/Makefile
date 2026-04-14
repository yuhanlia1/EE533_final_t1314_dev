IVERILOG ?= iverilog
VVP ?= vvp

ROOT_DIR := ..
TOP := tb_user_top_offload
BUILD_DIR := build

DEFINES ?= -DUDP_REG_ADDR_WIDTH=16 -DCPCI_NF2_DATA_WIDTH=32 -DNO_VCD
IVERILOG_FLAGS ?= -g2012 -Wall -I$(ROOT_DIR)/include $(DEFINES)

SRC := \
	$(ROOT_DIR)/src/fifo_bram.v \
	$(ROOT_DIR)/src/convertible_fifo.v \
	$(ROOT_DIR)/src/packet_action_selector.v \
	$(ROOT_DIR)/src/action_dispatcher.v \
	$(ROOT_DIR)/src/pipeline_control_regs.v \
	$(ROOT_DIR)/src/ann_task_ingress.v \
	$(ROOT_DIR)/src/ann_feature_unpack.v \
	$(ROOT_DIR)/src/ann_compute_core_simple.v \
	$(ROOT_DIR)/src/ann_cpu_gpu_compute_core.v \
	$(ROOT_DIR)/src/ann_result_packet_builder.v \
	$(ROOT_DIR)/src/ann_engine_wrapper.v \
	$(ROOT_DIR)/src/bram_wrapper.v \
	$(ROOT_DIR)/src/cpu_gpu_controller.v \
	$(ROOT_DIR)/src/gpu_platform_bridge.v \
	$(wildcard $(ROOT_DIR)/src/cpu/*.v) \
	$(wildcard $(ROOT_DIR)/src/gpu/*.v) \
	$(ROOT_DIR)/src/user_top.v \
	$(TOP).v

.PHONY: all run run-all unit verify clean

all: run

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/$(TOP).vvp: $(SRC) | $(BUILD_DIR)
	$(IVERILOG) $(IVERILOG_FLAGS) -o $@ $(SRC)

run: $(BUILD_DIR)/$(TOP).vvp
	$(VVP) $<

unit:
	$(MAKE) -C unit run

run-all: run unit

verify:
	bash $(ROOT_DIR)/scripts/verify_tb.sh tb_user_top_offload

clean:
	rm -rf $(BUILD_DIR)
