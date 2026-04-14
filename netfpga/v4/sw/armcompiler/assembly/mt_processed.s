.main:
    mov  r2, #0

.loop:
    cmp   r2, #7
    bge   .done
    ldr  r3, [r2]
    add  r3, r3, #1
    str  r3, [r2]
    b     .loop

.done:
    b     .done