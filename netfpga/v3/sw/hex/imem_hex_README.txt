Generated IMEM hex files for the uploaded testbenches.

CPU:
- cpu_modify_nop_safe.hex                -> tb_user_top_cpu_modify.v / init_program_nop_safe
- cpu_modify_word1_add1.hex              -> tb_user_top_cpu_modify.v / init_program_modify_word1_add1
- cpu_frontend_add1_1234.hex             -> tb_user_top_cpu_frontend_add1_1234.v / init_program

GPU:
- gpu_ptx_v2lane_imem.hex                -> tb_user_top_gpu_ptx.v / load_programs_v2

Example:
  ./load_cpu_imem_v2.sh cpu_frontend_add1_1234.hex
  ./load_gpu_imem_v2.sh gpu_ptx_v2lane_imem.hex
