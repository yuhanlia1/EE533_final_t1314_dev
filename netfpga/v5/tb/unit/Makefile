IVERILOG ?= iverilog
VVP ?= vvp

ROOT_DIR := ../..
BUILD_DIR := build
TESTS := tb_packet tb_communication_nn tb_communication_matrix tb_gpu_imem_guard

IVERILOG_FLAGS ?= -g2012 -Wall -I$(ROOT_DIR)/include

COMMON_SOURCES := \
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
	$(wildcard $(ROOT_DIR)/src/gpu/*.v)

.PHONY: all run run-all verify clean $(TESTS)

all: run

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/%.vvp: %.v $(COMMON_SOURCES) | $(BUILD_DIR)
	$(IVERILOG) $(IVERILOG_FLAGS) -o $@ $< $(COMMON_SOURCES)

$(TESTS): %: $(BUILD_DIR)/%.vvp
	$(VVP) $<

run: run-all

run-all: $(TESTS)

verify:
	bash $(ROOT_DIR)/scripts/verify_tb.sh $(TESTS)

clean:
	rm -rf $(BUILD_DIR)
