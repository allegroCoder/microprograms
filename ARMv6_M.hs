{-# LANGUAGE TypeFamilies #-}

-- NOTES
-- In this implementation of the ARMv6_M 11 groups of instructions are present.

module ARMv6_M (
    --module Control.Monad,
    ARMv6_M (..), Microprogram_v2 (..), Register (..), ComputationType (..),
    Address, Value,
    -- instructions available
    uncBranch, branchReg, storeImm, loadImm, storeBurst, loadBurst, arithOpsImm,
    arithOpsReg, storeReg, loadReg, branchPop, nop, branchMemReg, branchMemImm
    ) where

--import Control.Monad
import Microprogram_v2

class Microprogram_v2 m => ARMv6_M m where
    -- registers
    lr, apsr               :: Register m
    carry, overflow        :: Value
    -- arithmetic operations
    adcRegs                :: Register m -> Register m -> Value -> ComputationType m
    adcRegImm              :: Register m -> Value -> Value -> ComputationType m
    adcRegMem              :: Register m -> Address -> Value -> ComputationType m
    mulRegs                :: Register m -> Register m -> ComputationType m
    -- bitwise operations
    andRegs, xorRegs       :: Register m -> Register m -> ComputationType m
    andRegImm, xorRegImm   :: Register m -> Value -> ComputationType m
    notReg                 :: Register m -> ComputationType m
    notVal                 :: Value -> ComputationType m
    -- shifts TODO shifts always produce carry flag
    shrRegs, shlRegs       :: Register m -> Register m -> Value -> ComputationType m
    shrRegImm, shlRegImm   :: Register m -> Value -> Value -> ComputationType m
    -- additional functions implemented
    readMemoryBurst        :: Address -> m ()
    writeMemoryBurst       :: Address -> m ()
    bkptInstrDebugEvent    :: m ()
    updateN                :: Value -> m () -- Negative flag
    updateZ                :: Value -> m () -- Zero flag
    updateC                :: Value -> m () -- Carry flag
    updateV                :: Value -> m () -- Overflow flag
    convAndExtend          :: SignType m -> Value -> Value -> Register m -> Value -> Value
    convAndExtendImm       :: Value -> Value -> Value -> Value -> Value

-- *****************************************************************************
-- *                          ARMv6-M Basic functions                          *
-- *****************************************************************************

-- TODO Implement this functions
updateN :: ARMv6_M => Value -> m ()
updateN bit = do
    writeBit apsr 31 bit

updateZ :: ARMv6_M => Value -> m ()
updateZ result = do
    bit <- isZero result --TODO implement this function
    writeBit apsr 30 bit

updateC :: ARMv6_M => Value -> m ()
updateC bit = do
    writeBit apsr 29 bit

updateV :: ARMv6_M => Value -> m ()
updateV bit = do
    writeBit apsr 28 bit

-- *****************************************************************************
-- *                          ARMv6-M Specification                            *
-- *****************************************************************************

-- Memory burst operation - Ldm Stm
-- Load/Store a bunch of register from/to the memory
storeBurst :: ARMv6_M m => Register m -> m ()
storeBurst regBase = do
    memLocation <- readRegister regBase
    writeMemoryBurst memLocation
    incAndFetchInstruction

-- ADC (register) - Encoding T1
adc_RegT1 :: ARMv6_M m => Register m -> Register m -> m ()
adcT1 rm rdn = do
    shifted <- alu (shlRegImm rm 0 apsr[29]) -- APSR[29] = Carry flag
    result <- alu (adcRegImm rdn shifted apsr[29])
    writeRegister rdn result
    updateN result[31] --TODO Have a functionality to access any bit in a reg
    updateZ result
    updateC carry
    updateV overflow
    incAndFetchInstruction


-- ADD (immediate) - Encoding T1
add_ImmT1 :: ARMv6_M m => Register m -> Register m -> m ()
add_ImmT1 rn rd imm32  = do -- TODO imm32 should be extended from imm3 in the decoding function
    increment pc
    result <- alu (adcRegImm rn imm32 0)
    writeRegister rd result
    updateN result[31]
    updateZ result
    updateC carry
    updateV overflow
    incAndFetchInstruction

-- ADD (register) - Encoding T1
add_RegT1 :: ARMv6_M m => Register m -> Register m -> Register m -> m ()
add_RegT1 rm rn rd = do
    shifted <- alu (shlRegImm rm 0 apsr[29])
    result <- alu (adcRegImm rn shifted 0)
    writeRegister rd result
    updateN result[31]
    updateZ result
    updateC carry
    updateV overflow
    incAndFetchInstruction

-- ADD (SP + immediate) - Encoding T1
add_ImmSPT1 :: ARMv6_M m => Register m -> m ()
add_RegT1 rd imm32 = do
    result <- alu (adcRegImm sp imm32 0)
    writeRegister rd result
    incAndFetchInstruction

-- ADD (SP + register) - Encoding T1
add_RegSPT1 :: ARMv6_M m => Register m -> m ()
add_RegT1 d rdm = do -- TODO d is integer representation of PC and it is computed
                     -- extending rdm
    shifted <- alu (shlRegImm rdm 0 apsr[29])
    result <- alu (adcRegImm sp shifted 0)
    if d == 15
        then writeRegister pc result
        else writeRegister rdm result
             increment pc
    fetchInstruction

-- ADR - Encoding T1
adrT1 :: ARMv6_M m => Register m -> m ()
adrT1 rd imm32 = do
    result <- alu (adcRegImm pc imm32 0)
    writeRegister rd result
    incAndFetchInstruction

-- AND (register) - Encoding T1
andT1 :: ARMv6_M m => Register m -> Register m -> m ()
andT1 rm rdn = do
    shifted <- alu (shlRegImm rm 0 apsr[29])
    result <- alu (andRegImm rdn shifted)
    writeRegister rdn result
    updateN result[31]
    updateZ result
    updateC carry
    incAndFetchInstruction

-- ASR (immediate) - Encoding T1
asr_ImmT1 :: ARMv6_M m => Register m -> Register m -> m ()
asr_ImmT1 rm rd imm32 = do
    increment pc
    result <- alu (shrRegImm rm imm32 apsr[29])
    writeRegister rd result
    updateN result[31]
    updateZ result
    updateC carry
    incAndFetchInstruction

-- ASR (register) - Encoding T1
asr_RegT1 :: ARMv6_M m => Register m -> Register m -> Register m -> m ()
asr_RegT1 rd rn rm = do
    shift_n <- convAndExtend unsigned 31 0 rm 7 0 -- TODO convert and extend a portion of register
    result  <- alu (shrRegImm rn shift_n apsr[32])
    writeRegister rd result
    updateN result[31]
    updateZ result
    updateC carry
    incAndFetchInstruction

-- B (unconditional immediate) - Encoding T1
b :: ARMv6_M m => m ()
b imm32 = do
    nextInstrLocation <- alu (adcRegImm pc imm32 0)
    writeRegister pc nextInstrLocation
    readMemory nextInstrLocation ir

-- BIC (register) - Encoding T1
bic_RegT1 :: ARMv6_M m => Register m -> Register m -> m ()
bic_RegT1 rm rdn = do
    shifted <- alu (shlRegVal rm 0 apsr[29])
    shifted_negated <- alu (notVal shifted)
    result <- alu (andRegImm rdn shifted_negated)
    writeRegister rdn result
    updateN result[31]
    updateZ result
    updateC carry
    incAndFetchInstruction

-- BKPT (imm) - Encoding T1
bkpt_T1 :: ARMv6_M m => m ()
bkpt_T1 imm32 = do
    bkptInstrDebugEvent
    incAndFetchInstruction

-- BL (immediate) - Encoding T1
bl_ImmT1 :: ARMv6_M m => m ()
bl_ImmT1 imm32 = do
    currentPC <- readRegister pc
    lrTmp <- convAndExtendImm currentPC 31 1 1
    writeRegister lr lrTmp
    nextInstrLocation <- alu (adcRegMem pc imm32 0)
    writeRegister pc nextInstrLocation
    readMemory nextInstrLocation ir

-- TODO start hereinafter

-- BLX (register) - Encoding T1
blx_RegT1 :: ARMv6_M m => Register m -> m ()
blx_RegT1 rm = do
    currentPC <- readRegister pc
    writeRegister lr currentPC
    increment lr -- link to next instruction
    nextInstrLocation <- alu (addRegs pc rm)
    writeRegister pc nextInstrLocation
    readMemory nextInstrLocation ir

-- BX (register) - Encoding T1
bx_RegT1 :: ARMv6_M m => Register m -> m ()
bx_RegT1 rm = do
    nextInstrLocation <- alu (addRegs pc rm)
    writeRegister pc nextInstrLocation
    readMemory nextInstrLocation ir

-- CMN (register) - Encoding T1
cmn_RegT1 :: ARMv6_M m => Register m -> Register m -> m ()
cmn_RegT1 rn rm = do
    shifted <- alu (shlRegVal rm 0)
    result <- alu (addRegVal rm shifted) -- alu is supposed to update the flags
    incAndFetchInstruction

-- CMP (immediate) - Encoding T1
cmp_ImmT1 :: ARMv6_M m => Register m -> m ()
cmp_ImmT1 rn = do
    increment pc
    result <- alu (subRegImm rn)
    incAndFetchInstruction

-- CMP (register) - Encoding T1
cmp_RegT1 :: ARMv6_M m => Register m -> m ()
cmp_RegT1 rn rm = do
    shifted <- alu (shlRegVal rm 0)
    result <- alu (subRegVal rn shifted)
    incAndFetchInstruction

-- CPY
cpy :: ARMv6_M m => Register m -> Register m -> m ()
cpy rd rn = do
    value <- readRegister rn
    writeRegister rd value
    incAndFetchInstruction

-- EOR (register) - Encoding T1
eor_RegT1 :: ARMv6_M m => Register m -> Register m -> m ()
eor_RegT1 rdn rm = do
    shifted <- alu (shlRegVal rm 0)
    result <- alu (xorRegVal rdn shifted)
    writeRegister rdn result
    incAndFetchInstruction

-- LDM - Encoding T1
ldm_T1 :: ARMv6_M m => Register m -> m ()
ldm_T1 rn = do
    memLocation <- readRegister rn
    readMemoryBurst memLocation
    incAndFetchInstruction

-- LDR (immediate) - Encoding T1
ldr_ImmT1 :: ARMv6_M m => Register m -> Register m -> m ()
ldr_ImmT1 rt rn = do
    increment pc
    offset_addr = alu (addRegImm rn)
    readMemory offset_addr rt
    incAndFetchInstruction

-- LDR (literal: PC + Immediate) - Encoding T1
ldr_ImmPCT1 :: ARMv6_M m => Register m -> m ()
ldr_ImmPCT1 rt = do
    increment pc
    address = alu (addRegImm pc)
    readMemory address rt
    incAndFetchInstruction

-- LDR (register) - Encoding T1
ldr_RegT1 :: ARMv6_M m => Register m -> Register m -> Register m -> m ()
ldr_RegT1 rt rn rm = do
    offset <- alu (shlRegVal rm 0)
    offset_addr <- alu (addRegVal rn offset)
    readMemory offset_addr rt
    incAndFetchInstruction

-- LDRB (immediate) - Encoding T1
ldrb_ImmT1 :: ARMv6_M m => Register m -> Register m -> m ()
ldrb_ImmT1 rt rn = do
    increment pc
    offset_addr = alu (addRegImm rn)
    readMemory offset_addr rt -- TODO: this should read one single byte and extend it
    incAndFetchInstruction

-- LDRB (register) - Encoding T1
ldrb_RegT1 :: ARMv6_M m => Register m -> Register m -> Register m -> m ()
ldrb_RegT1 rt rn rm = do
    offset <- alu (shlRegVal rm 0)
    offset_addr <- alu (addRegVal rn offset)
    readMemory offset_addr rt -- TODO: this should read one single byte and extend it
    incAndFetchInstruction

-- LDRH (immediate) - Encoding T1
ldrh_ImmT1 :: ARMv6_M m => Register m -> Register m -> m ()
ldrh_ImmT1 rt rn = do
    increment pc
    offset_addr = alu (addRegImm rn)
    readMemory offset_addr rt -- TODO: this should read two bytes and extend it
    incAndFetchInstruction

-- LDRH (register) - Encoding T1
ldrh_RegT1 :: ARMv6_M m => Register m -> Register m -> Register m -> m ()
ldrh_RegT1 rt rn rm = do
    offset <- alu (shlRegVal rm 0)
    offset_addr <- alu (addRegVal rn offset)
    readMemory offset_addr rt -- TODO: this should read two bytes and extend it
    incAndFetchInstruction

-- LDRSB (register) - Encoding T1
ldrsb_RegT1 :: ARMv6_M m => Register m -> Register m -> Register m -> m ()
ldrsb_RegT1 rt rn rm = do
    offset <- alu (shlRegVal rm 0)
    offset_addr <- alu (addRegVal rn offset)
    readMemory offset_addr rt -- TODO: this should read one single byte and extend it with sign
    incAndFetchInstruction

-- LDRSH (register) - Encoding T1
ldrsh_RegT1 :: ARMv6_M m => Register m -> Register m -> Register m -> m ()
ldrsh_RegT1 rt rn rm = do
    offset <- alu (shlRegVal rm 0)
    offset_addr <- alu (addRegVal rn offset)
    readMemory offset_addr rt -- TODO: this should read two bytes and extend it with sign
    incAndFetchInstruction

-- LSL (immediate) - Encoding T1
lsl_ImmT1 :: ARMv6_M m => Register m -> Register m -> m ()
lsl_ImmT1 rd rm = do
    increment pc
    result <- alu(shlRegImm rm)
    writeRegister rd result
    incAndFetchInstruction

-- LSL (register) - Encoding T1
lsl_RegT1 :: ARMv6_M m => Register m -> Register m -> Register m -> m ()
lsl_RegT1 rd rn rm = do
    result <- alu(shlRegs rn rm) -- TODO only first byte is counted in rm
    writeRegister rd result
    incAndFetchInstruction

-- LSR (immediate) - Encoding T1
lsr_ImmT1 :: ARMv6_M m => Register m -> Register m -> m ()
lsr_ImmT1 rd rm = do
    increment pc
    result <- alu(shrRegImm rm)
    writeRegister rd result
    incAndFetchInstruction

-- LSR (register) - Encoding T1
lsr_RegT1 :: ARMv6_M m => Register m -> Register m -> Register m -> m ()
lsr_RegT1 rd rn rm = do
    result <- alu(shrRegs rn rm) -- TODO only first byte is counted in rm
    writeRegister rd result
    incAndFetchInstruction

-- MOV (immediate) - Encoding T1
mov_ImmT1 :: ARMv6_M m => Register m -> m ()
mov_ImmT1 rd = do
    address <- fetchAddressImmediate
    readMemory address rd
    incAndFetchInstruction

-- MOV (register) - Encoding T1
mov_RegT1 :: ARMv6_M m => Register m -> Register m -> m ()
mov_RegT1 rd rm = do
    result <- readRegister rm
    write register rd result
    incAndFetchInstruction

-- MUL (register) - Encoding T1
mul_T1 :: ARMv6_M m => Register m -> Register m -> Register m -> m ()
mul_T1 rdm rn = do
    result <- alu (mulRegs rdm rn)
    writeRegister rdm result
    incAndFetchInstruction

-- MVN (register) - Encoding T1
mvn_RegT1 :: ARMv6_M m => Register m -> Register m ->  m ()
mvn_RegT1 rd rm = do
    shifted <- alu (shlRegVal rm 0)
    result <- alu (notVal shifted)
    writeRegister rd result
    incAndFetchInstruction

-- NEG (alias for RSBS)
neg :: ARMv6_M m => Register m ->  Register m -> m ()
neg rd rm = do
    rsbs_ImmT1 rd rn 0

-- NOP already modelled inside basic architecture

-- ORR (register) - Encoding T1
orr_RegT1 ::  ARMv6_M m => Register m -> Register m -> m ()
orr_RegT1 rdn rm = do
    shifted <- alu (shlRegVal rm 0)
    result <- alu (orRegVal rdn shifted)
    writeRegister rdn result
    incAndFetchInstruction

-- REV - Encoding T1
rev_T1 ::  ARMv6_M m => Register m -> Register m -> m ()
rev_T1 rd rm = do
    result <- reverseResult word rm -- TODO reverse bytes ordering
    writeRegister rd result
    incAndFetchInstruction

-- REV16 - Encoding T1
rev16_T1 :: ARMv6_M m => Register m -> Register m -> m ()
rev16_T1 rd rm = do
    result <- reverseResult hword rm -- TODO reverse bytes ordering of half-word
    writeRegister rd result
    incAndFetchInstruction

-- REVSH - Encoding T1
revsh_T1 :: ARMv6_M m => Register m -> Register m -> m ()
revsh_T1 rd rm = do
    result <- signExtend 31 8 rm 7 0
    result <- movBits 7 0 rm 15 8
    writeRegister rd result
    incAndFetchInstruction