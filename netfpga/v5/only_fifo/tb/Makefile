IVERILOG ?= iverilog
VVP ?= vvp

TOP := user_top_tb
BUILD_DIR := build
ROOT_DIR := ../..

DEFINES ?= -DUDP_REG_ADDR_WIDTH=16 -DCPCI_NF2_DATA_WIDTH=32
IVERILOG_FLAGS ?= -g2012 -Wall -I$(ROOT_DIR)/include $(DEFINES)

SRC := \
	$(ROOT_DIR)/src/fifo_bram.v \
	$(ROOT_DIR)/src/convertible_fifo.v \
	$(ROOT_DIR)/src/packet_action_selector.v \
	$(ROOT_DIR)/src/action_dispatcher.v \
	$(ROOT_DIR)/src/network_stream_slice.v \
	$(ROOT_DIR)/src/tb_necessary/generic_regs_sim_stub.v \
	$(ROOT_DIR)/src/ann_task_ingress.v \
	$(ROOT_DIR)/src/ann_feature_unpack.v \
	$(ROOT_DIR)/src/ann_cpu_gpu_compute_core.v \
	$(ROOT_DIR)/src/ann_result_packet_builder.v \
	$(ROOT_DIR)/src/ann_engine_wrapper.v \
	$(ROOT_DIR)/src/bram_wrapper.v \
	$(ROOT_DIR)/src/tb_necessary/cpu_gpu_controller.v \
	$(ROOT_DIR)/src/tb_necessary/gpu_platform_bridge.v \
	$(ROOT_DIR)/src/cpu/alu_64_stage1.v \
	$(ROOT_DIR)/src/cpu/alu_64_stage2.v \
	$(ROOT_DIR)/src/cpu/arm_processor_top.v \
	$(ROOT_DIR)/src/cpu/decode_stage1.v \
	$(ROOT_DIR)/src/cpu/ex_stage1.v \
	$(ROOT_DIR)/src/cpu/ex_stage2.v \
	$(ROOT_DIR)/src/cpu/fetch_stage1.v \
	$(ROOT_DIR)/src/cpu/fetch_stage2.v \
	$(ROOT_DIR)/src/cpu/mem_RF.v \
	$(ROOT_DIR)/src/cpu/mem_data.v \
	$(ROOT_DIR)/src/cpu/mem_inst.v \
	$(ROOT_DIR)/src/cpu/mem_register_slice.v \
	$(ROOT_DIR)/src/cpu/mem_stage.v \
	$(ROOT_DIR)/src/cpu/wb_stage1.v \
	$(wildcard $(ROOT_DIR)/src/gpu/*.v) \
	$(ROOT_DIR)/src/user_top.v \
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
