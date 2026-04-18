.main:
  mov r0, #0
  ldr r1, [r0]
  add r2, r1, #1
  add r3, r2, #4
  cmp r3, #8
  bge .done
  mov r4, r3
.done:
  b .done

