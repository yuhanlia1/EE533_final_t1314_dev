.main:
  mov r0, #0
  mov r1, #0xA5
  str r1, [r0]

  mov r0, #1
  mov r1, #0x5A
  str r1, [r0]

  mov r0, #2
  mov r1, #0x3C
  str r1, [r0]

.done:
  b .done

