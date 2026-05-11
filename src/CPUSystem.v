`timescale 1ns / 1ps

// Top-level CPU controller — orchestrates instruction fetch, decode, and execute
module CPUSystem(
    input wire Clock,
    input wire Reset,
    output reg [11:0] T
);

    // Instruction field extraction wires
    wire [5:0] Opcode;
    wire [1:0] RegSel;
    wire [7:0] Address;
    wire [2:0] DestReg, SrcReg1, SrcReg2;

    // Control registers for the Register File
    reg [2:0] RF_OutASel, RF_OutBSel;
    reg [1:0] RF_FunSel;
    reg [3:0] RF_RegSel, RF_ScrSel;

    // ALU control
    reg [3:0] ALU_FunSel;
    reg       ALU_WF;

    // Address Register File control
    reg [1:0] ARF_OutCSel;
    reg       ARF_OutDSel;
    reg [1:0] ARF_FunSel;
    reg [2:0] ARF_RegSel;

    // Memory unit control
    reg IMU_CS, IMU_LH;
    reg DMU_WR, DMU_CS, DMU_FunSel;

    // Multiplexer selectors
    reg [1:0] MuxASel, MuxBSel;
    reg       MuxCSel;

    // Datapath observation wires
    wire [15:0] OutA, OutB, OutC, OutD, OutE;
    wire [15:0] ALUOut, IROut, MuxAOut, MuxBOut;
    wire [7:0]  MuxCOut;
    wire Z, C, N, O;

    // Instantiate the datapath
    ArithmeticLogicUnitSystem ALUSys(
        .RF_OutASel(RF_OutASel), .RF_OutBSel(RF_OutBSel),
        .RF_FunSel(RF_FunSel),  .RF_RegSel(RF_RegSel),
        .RF_ScrSel(RF_ScrSel),
        .ALU_FunSel(ALU_FunSel), .ALU_WF(ALU_WF),
        .ARF_OutCSel(ARF_OutCSel), .ARF_OutDSel(ARF_OutDSel),
        .ARF_FunSel(ARF_FunSel),   .ARF_RegSel(ARF_RegSel),
        .IMU_CS(IMU_CS), .IMU_LH(IMU_LH),
        .DMU_WR(DMU_WR), .DMU_CS(DMU_CS), .DMU_FunSel(DMU_FunSel),
        .MuxASel(MuxASel), .MuxBSel(MuxBSel), .MuxCSel(MuxCSel),
        .Clock(Clock),
        .OutA(OutA), .OutB(OutB), .OutC(OutC),
        .OutD(OutD), .OutE(OutE),
        .ALUOut(ALUOut), .IROut(IROut),
        .MuxAOut(MuxAOut), .MuxBOut(MuxBOut),
        .MuxCOut(MuxCOut),
        .Z(Z), .C(C), .N(N), .O(O)
    );

    // Decode instruction fields from IR output
    assign Opcode  = IROut[15:10];
    assign RegSel  = IROut[9:8];
    assign Address = IROut[7:0];
    assign DestReg = IROut[9:7];
    assign SrcReg1 = IROut[6:4];
    assign SrcReg2 = IROut[3:1];



    reg T_Reset;        // resets the timing counter back to T0
    reg cond_branch;      // evaluated branch condition

    // ----------------------------------------------------------------
    //  Helper: translate a 2-bit register index into a one-hot-low
    //          enable mask for the general-purpose register file
    // ----------------------------------------------------------------
    function [3:0] rf_enable_mask;
        input [1:0] idx;
        begin
            case (idx)
                2'd0: rf_enable_mask = 4'b0111;
                2'd1: rf_enable_mask = 4'b1011;
                2'd2: rf_enable_mask = 4'b1101;
                2'd3: rf_enable_mask = 4'b1110;
            endcase
        end
    endfunction

    // ----------------------------------------------------------------
    //  Helper: translate a 2-bit register index into a one-hot-low
    //          enable mask for the address register file
    // ----------------------------------------------------------------
    function [2:0] arf_enable_mask;
        input [1:0] idx;
        begin
            case (idx)
                2'd0, 2'd1: arf_enable_mask = 3'b011;   // PC
                2'd2:       arf_enable_mask = 3'b110;   // AR
                2'd3:       arf_enable_mask = 3'b101;   // SP
            endcase
        end
    endfunction

    // ----------------------------------------------------------------
    //  Helper: convert a 3-bit register code (1xx = RF) to the
    //          corresponding RF output-select value (000..011)
    // ----------------------------------------------------------------
    function [2:0] rf_out_index;
        input [2:0] regcode;
        begin
            case (regcode)
                3'b100:  rf_out_index = 3'd0;
                3'b101:  rf_out_index = 3'd1;
                3'b110:  rf_out_index = 3'd2;
                3'b111:  rf_out_index = 3'd3;
                default: rf_out_index = 3'd0;
            endcase
        end
    endfunction

    // ----- Timing shift-register: advances T on every rising edge -----
    always @(posedge Clock) begin
        if (~Reset || T_Reset)
            T <= 12'b0000_0000_0001;
        else
            T <= {T[10:0], T[11]};
    end

    // ===================== Main control logic =========================
    always @(*) begin
        // ---- safe defaults — keep everything idle ----
        RF_OutASel  = rf_out_index(SrcReg1);
        RF_OutBSel  = rf_out_index(SrcReg2);
        RF_FunSel   = 2'b00;
        RF_RegSel   = 4'b1111;
        RF_ScrSel   = 4'b1111;
        ALU_FunSel  = Opcode[3:0];
        ALU_WF      = 1'b0;
        ARF_OutCSel = 2'b00;
        ARF_OutDSel = 1'b0;
        ARF_FunSel  = 2'b00;
        ARF_RegSel  = 3'b111;
        IMU_CS      = 1'b0;
        IMU_LH      = 1'b0;
        DMU_WR      = 1'b0;
        DMU_CS      = 1'b0;
        DMU_FunSel  = 1'b0;
        MuxASel     = 2'b00;
        MuxBSel     = 2'b00;
        MuxCSel     = 1'b0;
        T_Reset   = 1'b0;
        cond_branch = 1'b0;

        // ---------- evaluate branch condition ----------
        case (Opcode)
            6'h00:   cond_branch = 1'b1;
            6'h01:   cond_branch = (Z == 1'b0);
            6'h02:   cond_branch = (Z == 1'b1);
            6'h03:   cond_branch = (N != O);
            6'h04:   cond_branch = (N == O && Z == 1'b0);
            6'h05:   cond_branch = (N != O || Z == 1'b1);
            6'h06:   cond_branch = (N == O);
            default: cond_branch = 1'b0;
        endcase

        // ---------- ALU function code look-up ----------
        case (Opcode)
            6'h09: ALU_FunSel = 4'b1011;   // LSL
            6'h0A: ALU_FunSel = 4'b1100;   // LSR
            6'h0B: ALU_FunSel = 4'b1101;   // ASR
            6'h0C: ALU_FunSel = 4'b1110;   // CSL
            6'h0D: ALU_FunSel = 4'b1111;   // CSR
            6'h0E: ALU_FunSel = 4'b0010;   // NOT
            6'h0F: ALU_FunSel = 4'b0111;   // AND
            6'h10: ALU_FunSel = 4'b1000;   // ORR
            6'h11: ALU_FunSel = 4'b1001;   // XOR
            6'h12: ALU_FunSel = 4'b1010;   // NAND
            6'h13: ALU_FunSel = 4'b0100;   // ADD
            6'h14: ALU_FunSel = 4'b0101;   // ADC
            6'h15: ALU_FunSel = 4'b0110;   // SUB
            6'h16: ALU_FunSel = 4'b0000;   // MOV (pass-through A)
            default: ALU_FunSel = 4'b0000;
        endcase

        // ==================== T0 : fetch low byte ====================
        if (T[0]) begin
            ARF_RegSel = 3'b011;
            ARF_FunSel = 2'b10;
            IMU_CS     = 1'b1;
            IMU_LH     = 1'b0;

        // ==================== T1 : fetch high byte ===================
        end else if (T[1]) begin
            ARF_RegSel = 3'b011;
            ARF_FunSel = 2'b10;
            IMU_CS     = 1'b1;
            IMU_LH     = 1'b1;

        // =============== T2+ : decode and execute ====================
        end else begin

            // ------- Group A : branch instructions (0x00 – 0x06) -------
            if (Opcode >= 6'h00 && Opcode <= 6'h06) begin
                if (T[2]) begin
                    if (cond_branch) begin
                        MuxBSel    = 2'b11;
                        ARF_RegSel = 3'b011;
                        ARF_FunSel = 2'b01;
                    end
                    T_Reset = 1'b1;
                end

            // ------- Group B : immediate load (0x17) -------
            end else if (Opcode == 6'h17) begin
                if (T[2]) begin
                    MuxASel   = 2'b11;
                    RF_RegSel = rf_enable_mask(RegSel);
                    RF_FunSel = 2'b01;
                    T_Reset = 1'b1;
                end

            // ------- Group C : increment / decrement (0x07, 0x08) ------
            end else if (Opcode == 6'h07 || Opcode == 6'h08) begin
                if (T[2]) begin
                    // Stage 1: copy source operand into scratch S1
                    if (SrcReg1[2] == 1'b0) begin
                        ARF_OutCSel = SrcReg1[1:0];
                        MuxASel     = 2'b01;
                    end else begin
                        RF_OutASel  = rf_out_index(SrcReg1);
                        MuxASel     = 2'b00;
                    end
                    RF_ScrSel   = 4'b0111;
                    RF_FunSel   = 2'b01;
                    ALU_FunSel  = 4'b0000;

                end else if (T[3]) begin
                    // Stage 2: apply inc/dec on S1
                    RF_ScrSel = 4'b0111;
                    RF_FunSel = (Opcode == 6'h07) ? 2'b10 : 2'b11;

                end else if (T[4]) begin
                    // Stage 3: route the result to destination with flag write
                    RF_OutASel = 3'b100;
                    ALU_FunSel = 4'b0000;
                    ALU_WF     = 1'b1;
                    if (DestReg[2] == 1'b0) begin
                        MuxBSel    = 2'b00;
                        ARF_RegSel = arf_enable_mask(DestReg[1:0]);
                        ARF_FunSel = 2'b01;
                    end else begin
                        MuxASel   = 2'b00;
                        RF_RegSel = rf_enable_mask(DestReg[1:0]);
                        RF_FunSel = 2'b01;
                    end
                    T_Reset = 1'b1;
                end

            // ------- Group D : single-source ALU ops (0x09–0x0E, 0x16) --
            end else if ((Opcode >= 6'h09 && Opcode <= 6'h0E) || Opcode == 6'h16) begin
                if (T[2]) begin
                    // Copy source to S1
                    if (SrcReg1[2] == 1'b0) begin
                        ARF_OutCSel = SrcReg1[1:0];
                        MuxASel     = 2'b01;
                    end else begin
                        RF_OutASel  = rf_out_index(SrcReg1);
                        MuxASel     = 2'b00;
                    end
                    RF_ScrSel  = 4'b0111;
                    RF_FunSel  = 2'b01;
                    ALU_FunSel = 4'b0000;

                end else if (T[3]) begin
                    // Apply ALU operation, write result to dest
                    RF_OutASel = 3'b100;
                    if (Opcode != 6'h16) ALU_WF = 1'b1;
                    if (DestReg[2] == 1'b0) begin
                        MuxBSel    = 2'b00;
                        ARF_RegSel = arf_enable_mask(DestReg[1:0]);
                        ARF_FunSel = 2'b01;
                    end else begin
                        MuxASel   = 2'b00;
                        RF_RegSel = rf_enable_mask(DestReg[1:0]);
                        RF_FunSel = 2'b01;
                    end
                    T_Reset = 1'b1;
                end

            // ------- Group E : two-source ALU ops (0x0F – 0x15) --------
            end else if (Opcode >= 6'h0F && Opcode <= 6'h15) begin
                if (T[2]) begin
                    // Transfer first operand into S1
                    if (SrcReg1[2] == 1'b0) begin
                        ARF_OutCSel = SrcReg1[1:0];
                        MuxASel     = 2'b01;
                    end else begin
                        RF_OutASel  = rf_out_index(SrcReg1);
                        MuxASel     = 2'b00;
                    end
                    RF_ScrSel  = 4'b0111;
                    RF_FunSel  = 2'b01;
                    ALU_FunSel = 4'b0000;

                end else if (T[3]) begin
                    // Transfer second operand into S2
                    if (SrcReg2[2] == 1'b0) begin
                        ARF_OutCSel = SrcReg2[1:0];
                        MuxASel     = 2'b01;
                    end else begin
                        RF_OutASel  = rf_out_index(SrcReg2);
                        MuxASel     = 2'b00;
                    end
                    RF_ScrSel  = 4'b1011;
                    RF_FunSel  = 2'b01;
                    ALU_FunSel = 4'b0000;

                end else if (T[4]) begin
                    // Compute and store
                    RF_OutASel = 3'b100;
                    RF_OutBSel = 3'b101;
                    ALU_WF     = 1'b1;
                    if (DestReg[2] == 1'b0) begin
                        MuxBSel    = 2'b00;
                        ARF_RegSel = arf_enable_mask(DestReg[1:0]);
                        ARF_FunSel = 2'b01;
                    end else begin
                        MuxASel   = 2'b00;
                        RF_RegSel = rf_enable_mask(DestReg[1:0]);
                        RF_FunSel = 2'b01;
                    end
                    T_Reset = 1'b1;
                end

            // ------- Group F : POP & RET (0x18, 0x1B) --------
            end else if (Opcode == 6'h18 || Opcode == 6'h1B) begin
                if (T[2]) begin
                    ARF_FunSel = 2'b10;
                    ARF_RegSel = 3'b101;   // SP increment
                end else if (T[3]) begin
                    ARF_OutDSel = 1'b1;
                    DMU_CS      = 1'b1;
                    DMU_WR      = 1'b0;
                    DMU_FunSel = 1'b0; // load low byte
                    ARF_FunSel = 2'b10;
                    ARF_RegSel = 3'b101;   // SP increment
                end else if (T[4]) begin
                    ARF_OutDSel = 1'b1;
                    DMU_CS      = 1'b1;
                    DMU_WR      = 1'b0;
                    DMU_FunSel = 1'b1; // load high byte
                end else if (T[5]) begin
                    if (Opcode == 6'h1B) begin
                        MuxBSel    = 2'b10;
                        ARF_RegSel = 3'b011; // Load PC from DMU output
                        ARF_FunSel = 2'b01;
                    end else begin
                        MuxASel   = 2'b10;
                        RF_RegSel = rf_enable_mask(RegSel); // Load RF from DMU output
                        RF_FunSel = 2'b01;
                    end
                    T_Reset = 1'b1;
                end
            end

            // ------- PSH (0x19) --------
            // High byte written at SP first, SP--, low byte at SP, SP--, T_Reset
            else if (Opcode == 6'h19) begin
                if (T[2]) begin
                    // Write HIGH byte at M[SP]
                    RF_OutASel  = {1'b0, RegSel};
                    ALU_FunSel  = 4'b0000; // MOV
                    MuxCSel     = 1'b1;    // high byte
                    ARF_OutDSel = 1'b1;    // SP as address
                    DMU_WR      = 1'b1;
                    DMU_CS      = 1'b1;
                    ARF_RegSel  = 3'b101;  // SP
                    ARF_FunSel  = 2'b11;   // SP--
                end else if (T[3]) begin
                    // Write LOW byte at M[SP] (now decremented)
                    RF_OutASel  = {1'b0, RegSel};
                    ALU_FunSel  = 4'b0000; // MOV
                    MuxCSel     = 1'b0;    // low byte
                    ARF_OutDSel = 1'b1;    // SP as address
                    DMU_WR      = 1'b1;
                    DMU_CS      = 1'b1;
                    ARF_RegSel  = 3'b101;  // SP
                    ARF_FunSel  = 2'b11;   // SP--
                    T_Reset     = 1'b1;
                end

            // ------- CALL (0x1A) --------
            // T[2]: PC → RF[RegSel] (save return address)
            // T[3]: write HIGH byte at M[SP], SP--
            // T[4]: write LOW  byte at M[SP], SP--
            // T[5]: PC ← Address field, T_Reset
            end else if (Opcode == 6'h1A) begin
                if (T[2]) begin
                    MuxASel     = 2'b01;
                    ARF_OutCSel = 2'b00;               // PC
                    RF_RegSel   = rf_enable_mask(RegSel); // save return address
                    RF_FunSel   = 2'b01;
                end else if (T[3]) begin
                    // Write HIGH byte at M[SP], SP--
                    RF_OutASel  = {1'b0, RegSel};
                    ALU_FunSel  = 4'b0000; // MOV
                    MuxCSel     = 1'b1;    // high byte
                    ARF_OutDSel = 1'b1;    // SP as address
                    DMU_WR      = 1'b1;
                    DMU_CS      = 1'b1;
                    ARF_RegSel  = 3'b101;  // SP
                    ARF_FunSel  = 2'b11;   // SP--
                end else if (T[4]) begin
                    // Write LOW byte at M[SP] (decremented), SP--
                    RF_OutASel  = {1'b0, RegSel};
                    ALU_FunSel  = 4'b0000; // MOV
                    MuxCSel     = 1'b0;    // low byte
                    ARF_OutDSel = 1'b1;    // SP as address
                    DMU_WR      = 1'b1;
                    DMU_CS      = 1'b1;
                    ARF_RegSel  = 3'b101;  // SP
                    ARF_FunSel  = 2'b11;   // SP--
                end else if (T[5]) begin
                    MuxBSel    = 2'b11;    // Address field → PC
                    ARF_RegSel = 3'b011;
                    ARF_FunSel = 2'b01;
                    T_Reset    = 1'b1;
                end
            end

            // ------- LDR (0x1C) : DSTREG ← M[AR] --------
            // AR is incremented between T[2] and T[3] so the two reads hit consecutive addresses
            else if (Opcode == 6'h1C) begin
                if (T[2]) begin
                    ARF_OutDSel = 1'b0;   // AR as DMU address
                    DMU_CS      = 1'b1;
                    DMU_WR      = 1'b0;   // read
                    DMU_FunSel  = 1'b0;   // → DR[7:0] low byte
                    ARF_RegSel  = 3'b110; // AR
                    ARF_FunSel  = 2'b10;  // AR++
                end else if (T[3]) begin
                    ARF_OutDSel = 1'b0;   // AR (now incremented) as DMU address
                    DMU_CS      = 1'b1;
                    DMU_WR      = 1'b0;   // read
                    DMU_FunSel  = 1'b1;   // → DR[15:8] high byte
                end else if (T[4]) begin
                    // Write full 16-bit DMUOut to destination register
                    if (DestReg[2] == 1'b0) begin
                        MuxBSel    = 2'b10; // DMUOut
                        ARF_RegSel = arf_enable_mask(DestReg[1:0]);
                        ARF_FunSel = 2'b01;
                    end else begin
                        MuxASel   = 2'b10; // DMUOut
                        RF_RegSel = rf_enable_mask(DestReg[1:0]);
                        RF_FunSel = 2'b01;
                    end
                    T_Reset = 1'b1;
                end

            // ------- STR (0x1D) : M[AR] ← SREG1 --------
            // If SREG1 is an ARF register, copy it to a scratch RF register first (T[2]),
            // then write both bytes to DMU (T[3], T[4]), then T_Reset.
            end else if (Opcode == 6'h1D) begin
                if (T[2]) begin
                    if (SrcReg1[2] == 1'b0) begin
                        // Source is ARF — route through MuxA into scratch S1
                        ARF_OutCSel = SrcReg1[1:0];
                        MuxASel     = 2'b01;
                        RF_ScrSel   = 4'b0111; // S1
                        RF_FunSel   = 2'b01;
                        ALU_FunSel  = 4'b0000; // MOV (pass-through)
                    end
                    // If SrcReg1 is already RF, no staging needed — go straight to write in T[3]
                end else if (T[3]) begin
                    // Write low byte of SREG1 → M[AR], then AR++
                    if (SrcReg1[2] == 1'b0) begin
                        RF_OutASel = 3'b100; // S1 (staged ARF value)
                    end else begin
                        RF_OutASel = rf_out_index(SrcReg1); // direct RF source
                    end
                    ALU_FunSel  = 4'b0000; // MOV
                    MuxCSel     = 1'b0;    // low byte → DMU
                    ARF_OutDSel = 1'b0;    // AR as DMU address
                    DMU_CS      = 1'b1;
                    DMU_WR      = 1'b1;    // write
                    ARF_RegSel  = 3'b110;  // AR
                    ARF_FunSel  = 2'b10;   // AR++
                end else if (T[4]) begin
                    // Write high byte of SREG1 → M[AR+1]
                    if (SrcReg1[2] == 1'b0) begin
                        RF_OutASel = 3'b100; // S1
                    end else begin
                        RF_OutASel = rf_out_index(SrcReg1);
                    end
                    ALU_FunSel  = 4'b0000; // MOV
                    MuxCSel     = 1'b1;    // high byte → DMU
                    ARF_OutDSel = 1'b0;    // AR as DMU address (incremented)
                    DMU_CS      = 1'b1;
                    DMU_WR      = 1'b1;    // write
                    T_Reset     = 1'b1;
                end
            end

            // ------- LDA (0x1E) : Rx ← M[ADDRESS] --------
            // Load the 8-bit immediate ADDRESS field into AR first, then do a two-cycle read.
            else if (Opcode == 6'h1E) begin
                if (T[2]) begin
                    // AR ← zero-extended Address field (MuxBSel=2'b11 routes IROut[7:0])
                    MuxBSel    = 2'b11;
                    ARF_RegSel = 3'b110; // AR
                    ARF_FunSel = 2'b01;  // load
                end else if (T[3]) begin
                    ARF_OutDSel = 1'b0;   // AR as DMU address
                    DMU_CS      = 1'b1;
                    DMU_WR      = 1'b0;   // read
                    DMU_FunSel  = 1'b0;   // → DR[7:0] low byte
                    ARF_RegSel  = 3'b110; // AR
                    ARF_FunSel  = 2'b10;  // AR++
                end else if (T[4]) begin
                    ARF_OutDSel = 1'b0;   // AR (incremented) as DMU address
                    DMU_CS      = 1'b1;
                    DMU_WR      = 1'b0;   // read
                    DMU_FunSel  = 1'b1;   // → DR[15:8] high byte
                end else if (T[5]) begin
                    // Rx ← full 16-bit DMUOut
                    MuxASel   = 2'b10;    // DMUOut
                    RF_RegSel = rf_enable_mask(RegSel);
                    RF_FunSel = 2'b01;
                    T_Reset   = 1'b1;
                end

            // ------- STA (0x1F) : M[ADDRESS] ← Rx --------
            // Load the 8-bit immediate ADDRESS into AR, then write both bytes of Rx to DMU.
            end else if (Opcode == 6'h1F) begin
                if (T[2]) begin
                    // AR ← zero-extended Address field
                    MuxBSel    = 2'b11;
                    ARF_RegSel = 3'b110; // AR
                    ARF_FunSel = 2'b01;  // load
                end else if (T[3]) begin
                    // Write low byte of Rx → M[AR], AR++
                    RF_OutASel  = {1'b0, RegSel};
                    ALU_FunSel  = 4'b0000; // MOV
                    MuxCSel     = 1'b0;    // low byte
                    ARF_OutDSel = 1'b0;    // AR as DMU address
                    DMU_CS      = 1'b1;
                    DMU_WR      = 1'b1;    // write
                    ARF_RegSel  = 3'b110;  // AR
                    ARF_FunSel  = 2'b10;   // AR++
                end else if (T[4]) begin
                    // Write high byte of Rx → M[AR+1]
                    RF_OutASel  = {1'b0, RegSel};
                    ALU_FunSel  = 4'b0000; // MOV
                    MuxCSel     = 1'b1;    // high byte
                    ARF_OutDSel = 1'b0;    // AR as DMU address (incremented)
                    DMU_CS      = 1'b1;
                    DMU_WR      = 1'b1;    // write
                    T_Reset     = 1'b1;
                end

            // ------- LDT (0x20) : Rx ← M[AR + OFFSET] --------
            // Compute effective address AR+OFFSET into AR using scratch registers,
            // then perform a two-cycle DMU read.
            // T[2]: OFFSET (Address field, zero-extended) → S1
            // T[3]: AR → S2
            // T[4]: AR ← S1 + S2  (effective address)
            // T[5]: read DR[7:0] from M[AR], AR++
            // T[6]: read DR[15:8] from M[AR+1]
            // T[7]: Rx ← DMUOut, T_Reset
            end else if (Opcode == 6'h20) begin
                if (T[2]) begin
                    // S1 ← OFFSET (zero-extended 8-bit Address field via MuxA=2'b11)
                    MuxASel    = 2'b11;
                    ALU_FunSel = 4'b0000; // MOV
                    RF_ScrSel  = 4'b0111; // S1
                    RF_FunSel  = 2'b01;
                end else if (T[3]) begin
                    // S2 ← AR (route AR through MuxA)
                    ARF_OutCSel = 2'b10;   // AR
                    MuxASel     = 2'b01;
                    ALU_FunSel  = 4'b0000; // MOV
                    RF_ScrSel   = 4'b1011; // S2
                    RF_FunSel   = 2'b01;
                end else if (T[4]) begin
                    // AR ← S1 + S2
                    RF_OutASel = 3'b100;   // S1 (OFFSET)
                    RF_OutBSel = 3'b101;   // S2 (AR)
                    ALU_FunSel = 4'b0100;  // ADD
                    MuxBSel    = 2'b00;    // ALUOut → ARF
                    ARF_RegSel = 3'b110;   // AR
                    ARF_FunSel = 2'b01;    // load
                end else if (T[5]) begin
                    // Read low byte from M[AR], AR++
                    ARF_OutDSel = 1'b0;
                    DMU_CS      = 1'b1;
                    DMU_WR      = 1'b0;
                    DMU_FunSel  = 1'b0;   // → DR[7:0]
                    ARF_RegSel  = 3'b110; // AR
                    ARF_FunSel  = 2'b10;  // AR++
                end else if (T[6]) begin
                    // Read high byte from M[AR+1]
                    ARF_OutDSel = 1'b0;
                    DMU_CS      = 1'b1;
                    DMU_WR      = 1'b0;
                    DMU_FunSel  = 1'b1;   // → DR[15:8]
                end else if (T[7]) begin
                    // Rx ← full 16-bit DMUOut
                    MuxASel   = 2'b10;
                    RF_RegSel = rf_enable_mask(RegSel);
                    RF_FunSel = 2'b01;
                    T_Reset   = 1'b1;
                end

            // ------- STT (0x21) : M[AR + OFFSET] ← Rx --------
            // Same effective-address computation as LDT, then write both bytes of Rx.
            // T[2]: OFFSET → S1
            // T[3]: AR → S2
            // T[4]: AR ← S1 + S2
            // T[5]: write low byte of Rx → M[AR]
            // T[6]: write high byte of Rx → M[AR], T_Reset
            end else if (Opcode == 6'h21) begin
                if (T[2]) begin
                    MuxASel    = 2'b11;
                    ALU_FunSel = 4'b0000;
                    RF_ScrSel  = 4'b0111; // S1 ← OFFSET
                    RF_FunSel  = 2'b01;
                end else if (T[3]) begin
                    ARF_OutCSel = 2'b10;   // AR
                    MuxASel     = 2'b01;
                    ALU_FunSel  = 4'b0000;
                    RF_ScrSel   = 4'b1011; // S2 ← AR
                    RF_FunSel   = 2'b01;
                end else if (T[4]) begin
                    RF_OutASel = 3'b100;   // S1 (OFFSET)
                    RF_OutBSel = 3'b101;   // S2 (AR)
                    ALU_FunSel = 4'b0100;  // ADD
                    MuxBSel    = 2'b00;    // ALUOut → ARF
                    ARF_RegSel = 3'b110;   // AR
                    ARF_FunSel = 2'b01;    // AR ← OFFSET + AR
                end else if (T[5]) begin
                    // Write low byte of Rx → M[AR], AR++
                    RF_OutASel  = {1'b0, RegSel};
                    ALU_FunSel  = 4'b0000;
                    MuxCSel     = 1'b0;    // low byte
                    ARF_OutDSel = 1'b0;    // AR
                    DMU_CS      = 1'b1;
                    DMU_WR      = 1'b1;
                    ARF_RegSel  = 3'b110;  // AR
                    ARF_FunSel  = 2'b10;   // AR++
                end else if (T[6]) begin
                    // Write high byte of Rx → M[AR]
                    RF_OutASel  = {1'b0, RegSel};
                    ALU_FunSel  = 4'b0000;
                    MuxCSel     = 1'b1;    // high byte
                    ARF_OutDSel = 1'b0;    // AR
                    DMU_CS      = 1'b1;
                    DMU_WR      = 1'b1;
                    T_Reset     = 1'b1;
                end
            end

        // ---- Global reset override (active-low) ----
        if (~Reset) begin
            RF_FunSel  = 2'b00;
            RF_RegSel  = 4'b0000;
            RF_ScrSel  = 4'b0000;
            ARF_FunSel = 2'b00;
            ARF_RegSel = 3'b000;
        end
        end // end else begin (T2+ decode/execute)
    end // end always @(*)

endmodule
