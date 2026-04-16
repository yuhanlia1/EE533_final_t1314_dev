.main:
  mov   r2, r2
  ldrt  r10, [r0]
  add   r10, r10, #1
  mov   r2, #3
  mov   r3, #0
  mov   r1, #5

.loop:
  cmp   r2, r10
  bge   .done

  ldr   r3, [r2]
  add   r3, r3, r1
  str   r3, [r2]

  add   r2, r2, #4
  b     .loop

.done:
