.main:
  mov r0, #0
  mov r1, #0xA5
  mov r5, r5
  str r1, [r0]
  mov r0, #1
  mov r1, #0x5A
  mov r5, r5
  str r1, [r0]
  mov r0, #2
  mov r1, #0x3C
  mov r5, r5
  str r1, [r0]
.done:
  b .done
