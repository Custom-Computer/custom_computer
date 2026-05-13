       BRA 0x8C             # This instruction is written to the memory address 0x00,
                            # The first instruction must be written to address 0x8C
.org 0x8C
       IMM R1, 0x06         # R1 is used for iteration number
       IMM R3, 0xB0
       MOV AR, R3           # AR is used to track data address: starts from 0xB0
       LDR R2                     # R2 ← M[AR]
       INC AR, AR           # AR ← AR + 1 (Next Data)
       DEC R1, R1           # R1 ← R1 – 1 (Decrement Iteration Counter)
LABEL: LDR R4               # R4 ← M[AR]
       SUB R3, R4, R2
       BLE SKIP             # SKIP if N!=O | Z==1
       MOV R2, R4
SKIP:  INC AR, AR           # AR ← AR + 1 (Next Data)
       DEC R1, R1           # R1 ← R1 – 1 (Decrement Iteration Counter)
       BNE LABEL            # Go back to LABEL if Z=0 (Iteration Counter > 0)
       STR R2
