#ifdef __arm__
#ifndef __aarch64__

.text
.align 5
.global MatmulInt8Neon32
#ifndef __APPLE__
.type MatmulInt8Neon32, %function
#endif


  //                                              int8 RHS 16x2 block
  //                                              /-----------------|
  //                                              |d8.b[0]  d10.b[0]|
  //                                              |  ...      ...   |
  //                                              |d8.b[7]  d10.b[7]|
  //                                              |d9.b[0]  d11.b[0]|
  //                                              |  ...      ...   |
  //                                              |d9.b[7]  d11.b[7]|
  //                                              \-----------------/
  //    int8 LHS 4x16 block
  //  /---------------------------------------\   /------------------|
  //  |d0.b[0] ... d0.b[7] d1.b[0] ... d1.b[7]|   |  q6(q14) q7(q2) |
  //  |d2.b[0] ... d2.b[7] d3.b[0] ... d3.b[7]|   |  q8(q15) q9(q3) |
  //  (Reload d0, d1, d2, d3)
  //  |d0.b[0] ... d0.b[7] d1.b[0] ... d1.b[7]|   |  q10(q14) q11(q2) |
  //  |d2.b[0] ... d2.b[7] d3.b[0] ... d3.b[7]|   |  q12(q15) q13(q3) |
  //  \---------------------------------------/   \-----------------/
  //                                         128-bit accumulators 4x2 block
  //
//void MatmulInt8Neon32(const int8_t *a, const int8_t *b, int8_t *dst, int row, int col, int deep16, 
//                      const int *input_sums, const int *weight_bias, int act_min, int act_max, int out_zp,
//                      int multiplier, int left_shift, int right_shift, int stride);
// #-52: a, #-48: b, #-44: dst, #-40: row
// #0: col, #4: deep16, #8: input_sums, #12: weight_bias, #16: act_min, #20: act_max, #24: out_zp
// #28: multiplier, #32: left_shift, #36: right_shift, #40: stride

MatmulInt8Neon32:
  push {r0-r11, lr}
  vpush {q4-q7}
  add sp, sp, #116

  ldr r4, [sp]            // col
  mov r7, #2
  ldr r8, [sp, #4]        // deep16
  mul r9, r7, r8          // the sride of b
  ldr r7, [sp, #40]       // output stride

L1:
  cmp r4, #0    // if at the end of col
  ble End1

  ldr r0, [sp, #-52]   // reload a ptr
  ldr r3, [sp, #-40]   // reset row counter
  ldr r6, [sp, #8]      // reload intpu_sums ptr
L2:
  cmp r3, #0    // if at the end of row
  ble End2

  ldr r1, [sp, #-48]    // reload b ptr
  ldr r8, [sp, #12]     // reload weight_bias ptr
  ldr r5, [sp, #4]      // reset deep16
  vmov.i32 q6, #0
  vmov.i32 q7, #0
  vmov.i32 q8, #0
  vmov.i32 q9, #0
  vmov.i32 q10, #0
  vmov.i32 q11, #0
  vmov.i32 q12, #0
  vmov.i32 q13, #0
L3:
  cmp r5, #0
  beq End3

  vld1.8 {d0, d1, d2, d3}, [r0]!
  vld1.8 {d8, d9, d10, d11}, [r1]!
  vmull.s8 q14, d0, d8
  vmull.s8 q2, d0, d10
  vmull.s8 q15, d2, d8
  vmull.s8 q3, d2, d10
  vmlal.s8 q14, d1, d9
  vmlal.s8 q2, d1, d11
  vmlal.s8 q15, d3, d9
  vmlal.s8 q3, d3, d11

  vpadal.s16 q6, q14
  vpadal.s16 q7, q2
  vpadal.s16 q8, q15
  vpadal.s16 q9, q3

  vld1.8 {d0, d1, d2, d3}, [r0]!
  vmull.s8 q14, d0, d8
  vmull.s8 q2, d0, d10
  vmull.s8 q15, d2, d8
  vmull.s8 q3, d2, d10
  vmlal.s8 q14, d1, d9
  vmlal.s8 q2, d1, d11
  vmlal.s8 q15, d3, d9
  vmlal.s8 q3, d3, d11

  vpadal.s16 q10, q14
  vpadal.s16 q11, q2
  vpadal.s16 q12, q15
  vpadal.s16 q13, q3
  sub r5, r5, #16  // deep16 -= 16
  b L3

End3:
  vpadd.i32 d0, d12, d13
  vpadd.i32 d1, d14, d15
  vpadd.i32 d2, d16, d17
  vpadd.i32 d3, d18, d19
  vpadd.i32 d4, d20, d21
  vpadd.i32 d5, d22, d23
  vpadd.i32 d6, d24, d25
  vpadd.i32 d7, d26, d27

  vpadd.i32 d28, d0, d1
  vpadd.i32 d29, d2, d3
  vpadd.i32 d30, d4, d5
  vpadd.i32 d31, d6, d7

/* 
  // Add weight_bias
  vld1.32 {d26}, [r8]!
  vadd.i32 d28, d28, d26
  vadd.i32 d29, d29, d26
  vadd.i32 d30, d30, d26
  vadd.i32 d31, d31, d26

  // Substract input_sums
  vld1.32 {d24, d25}, [r6]!
  vdup.32 d20, d24[0]
  vdup.32 d21, d24[1]
  vdup.32 d22, d25[0]
  vdup.32 d23, d25[1]
  vsub.s32 d28, d28, d20
  vsub.s32 d29, d29, d21
  vsub.s32 d30, d30, d22
  vsub.s32 d31, d31, d23

  // Apply left shift
  ldr r10, [sp, #32]
  vdup.32 q9, r10
  vshl.s32 q14, q14, q9
  vshl.s32 q15, q15, q9

  // Apply the fixed-point part of the multiplier
  ldr r10, [sp, #28]
  vdup.32 q8, r10
  vqrdmulh.s32 q14, q14, q8
  vqrdmulh.s32 q15, q15, q8

  // Apply right shift
  ldr r10, [sp, #36]
  vdup.32 q7, r10
  vand q6, q7, q14
  vshr.s32 q6, q6, #31
  vqadd.s32 q14, q14, q6
  vrshl.s32 q14, q14, q7
  vand q5, q7, q15
  vshr.s32 q5, q5, #31
  vqadd.s32 q15, q15, q5
  vrshl.s32 q15, q15, q7

  // Add the destination zero point
  ldr r10, [sp, #24]
  vdup.32 q4, r10
  vadd.i32 q14, q14, q4
  vadd.i32 q15, q15, q4

  // Apply the act_min bound
  ldr r10, [sp, #16]
  vdup.32 q3, r10
  vmax.s32 q14, q14, q3
  vmax.s32 q15, q15, q3

  // Apply the act_max bound
  ldr r10, [sp, #20]
  vdup.32 q2, r10
  vmin.s32 q14, q14, q2
  vmin.s32 q15, q15, q2
*/

  // Cast-and-saturate from int32 to int16
  vqmovn.s32 d28, q14
  vqmovn.s32 d29, q15

  // Cast-and-saturate from int16 to int8
  vqmovn.s16 d30, q14

  // start to write
  cmp r4, #2
  bge WriteCol2
  cmp r4, #1
  beq WriteCol1
  b EndWrite

WriteCol2:
  vst1.16 {d30[0]}, [r2], r7  
  cmp r3, #1
  beq EndWrite
  vst1.16 {d30[1]}, [r2], r7  
  cmp r3, #2
  beq EndWrite  
  vst1.16 {d30[2]}, [r2], r7  
  cmp r3, #3
  beq EndWrite  
  vst1.16 {d30[3]}, [r2], r7  
  b EndWrite

WriteCol1:
  vst1.8 {d30[0]}, [r2], r7  
  cmp r3, #1
  beq EndWrite
  vst1.8 {d30[2]}, [r2], r7  
  cmp r3, #2
  beq EndWrite
  vst1.8 {d30[4]}, [r2], r7  
  cmp r3, #3
  beq EndWrite
  vst1.8 {d30[6]}, [r2], r7  
  b EndWrite

EndWrite:
  sub r3, r3, #4   // a row counter -= 4
  b L2

End2:
  sub r4, r4, #2      // b col counter -= 2
  ldr r1, [sp, #-48]  // b ptr + stride
  add r1, r1, r9    
  str r1, [sp, #-48]
  ldr r8, [sp, #12]   // weight_bias + stride
  add r8, r8, #8
  str r8, [sp, #12]
  ldr r2, [sp, #-44]  // dst ptr + offset
  add r2, r2, #2
  str r2, [sp, #-44]
  b L1

End1:
  sub sp, sp, #116
  vpop {q4-q7}
  pop {r0-r11, pc}
#endif
#endif
