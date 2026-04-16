.main:
  mov r10, #128
  mov r0, #0
  mov r1, #0
  mov r2, #1
  mov r3, #128
  mov r4, #1536
  lsl r4, r4, #1
  mov r5, #32
  mov r6, #1024
  str r0, [r10, #8]
  str r1, [r10, #12]
  str r2, [r10, #16]
  str r3, [r10, #32]
  str r4, [r10, #40]
  str r5, [r10, #48]
  str r6, [r10, #56]
.done:
  b .done
