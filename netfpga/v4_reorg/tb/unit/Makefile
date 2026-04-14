IVERILOG ?= iverilog
VVP ?= vvp

ROOT_DIR := ../..
BUILD_DIR := build
TESTS := tb_packet tb_communication_nn tb_communication_matrix

IVERILOG_FLAGS ?= -g2012 -Wall -I$(ROOT_DIR)/include

COMMON_SOURCES := \
	$(ROOT_DIR)/src/bram_wrapper.v \
	$(ROOT_DIR)/src/cpu_gpu_controller.v \
	$(ROOT_DIR)/src/gpu_platform_bridge.v \
	$(wildcard $(ROOT_DIR)/src/cpu/*.v) \
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
