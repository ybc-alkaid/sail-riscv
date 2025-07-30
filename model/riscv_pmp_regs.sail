/*=======================================================================================*/
/*  This Sail RISC-V architecture model, comprising all files and                        */
/*  directories except where otherwise noted is subject the BSD                          */
/*  two-clause license in the LICENSE file.    // Check if MML (Machine Mode Lockdown) bit is set
  if mseccfg[MML] == bitone then {                                          */
/*                                                                                       */
/*  SPDX-License-Identifier: BSD-2-Clause                                                */
/*=======================================================================================*/

/* Platform configuration */

/* How many PMP entries are implemented. This must be 0, 16 or 64 (this is checked at runtime). */
let sys_pmp_count : {0, 16, 64} = config memory.pmp.count

/* G parameter that specifies the PMP grain size. The grain size is 2^(G+2), e.g.
   G=0 -> 4 bytes, G=10 -> 4096 bytes. */
let sys_pmp_grain : range(0, 63) = config memory.pmp.grain

/* PMP configuration entries */

enum PmpAddrMatchType = {OFF, TOR, NA4, NAPOT}

val pmpAddrMatchType_of_bits : bits(2) -> PmpAddrMatchType
function pmpAddrMatchType_of_bits(bs) = {
  match bs {
    0b00 => OFF,
    0b01 => TOR,
    0b10 => NA4,
    0b11 => NAPOT
  }
}

val pmpAddrMatchType_to_bits : PmpAddrMatchType -> bits(2)
function pmpAddrMatchType_to_bits(bs) = {
  match bs {
    OFF   => 0b00,
    TOR   => 0b01,
    NA4   => 0b10,
    NAPOT => 0b11
  }
}

bitfield Pmpcfg_ent : bits(8) = {
  L : 7,        /* locking */
  A : 4 .. 3,   /* address match type, encoded as above */

  /* permissions */
  X : 2,        /* execute */
  W : 1,        /* write */
  R : 0         /* read */
}

register pmpcfg_n : vector(64, Pmpcfg_ent)
register pmpaddr_n : vector(64, xlenbits)

/*=======================================================================================*/
/*  PMP/SPMP Resource Sharing                                                            */
/*                                                                                       */
/*  The mpmpdeleg CSR controls the sharing of PMP_Resource between PMP and SPMP.       */
/*  Each PMP_Resource consists of an address CSR, a configuration CSR, and associated  */
/*  micro-architecture state.                                                           */
/*=======================================================================================*/

/* mpmpdeleg CSR format:
 * Bits [15:7]: Reserved (WPRI)
 * Bits [6:0]: pmpnum - Number of PMP entries (0-64)
 * 
 * Resource allocation:
 * - PMP_Resource[0] to PMP_Resource[pmpnum-1] are allocated to PMP
 * - PMP_Resource[pmpnum] to PMP_Resource[63] are allocated to SPMP
 * 
 * Default reset value: pmpnum = 0b100_0000 (64, all resources to PMP)
 */
bitfield Mpmpdeleg_ent : bits(16) = {
  pmpnum : 6 .. 0  /* Number of PMP entries (0-64) */
}

register mpmpdeleg : Mpmpdeleg_ent

/* Get the current PMP/SPMP split point */
function getPmpNum() -> nat = unsigned(mpmpdeleg[pmpnum])

/* Check if a resource index belongs to PMP (true) or SPMP (false) */
function isPmpResource(idx: nat) -> bool = idx < getPmpNum()

/* Get the actual number of available SPMP entries */
function getSpmpEntryCount() -> nat = {
  let pmp_count = getPmpNum();
  if pmp_count >= 64 then 0 else 64 - pmp_count
}

/* Convert SPMP software index to hardware resource index */
function spmpSwToHwIndex(sw_idx: nat) -> nat = getPmpNum() + sw_idx

/* Convert hardware resource index to SPMP software index */
function spmpHwToSwIndex(hw_idx: nat) -> nat = {
  let pmp_num = getPmpNum();
  if hw_idx >= pmp_num then hw_idx - pmp_num else 0
}

/* Validate pmpnum value according to constraints:
 * - RV32: must be multiple of 4
 * - RV64: must be multiple of 8  
 * - Must be in range [0, 64]
 */
function isValidPmpNum(pmpnum: nat) -> bool = {
  let alignment = if xlen == 32 then 4 else 8;
  (pmpnum <= 64) & ((pmpnum % alignment) == 0)
}

/* Check if any PMP entry in the range [start, end) is locked */
function anyPmpLocked(start: nat, end_: nat) -> bool = {
  if start >= end_ then false
  else if start >= 64 then false
  else if end_ > 64 then anyPmpLocked(start, 64)
  else {
    (pmpcfg_n[start][L] == 0b1) | anyPmpLocked(start + 1, end_)
  }
}

/* Reset mpmpdeleg register to default value */
function reset_mpmpdeleg() -> unit = {
  // Default: all 64 resources allocated to PMP (pmpnum = 64)
  mpmpdeleg = [mpmpdeleg with pmpnum = 0b100_0000];
}

/* Packing and unpacking pmpcfg regs for xlen-width accesses */

function pmpReadCfgReg(n : range(0, 15)) -> xlenbits = {
  if xlen == 32
  then {
    pmpcfg_n[n*4 + 3].bits @
    pmpcfg_n[n*4 + 2].bits @
    pmpcfg_n[n*4 + 1].bits @
    pmpcfg_n[n*4 + 0].bits
  }
  else {
    assert(n % 2 == 0, "Unexpected pmp config reg read");
    pmpcfg_n[n*4 + 7].bits @
    pmpcfg_n[n*4 + 6].bits @
    pmpcfg_n[n*4 + 5].bits @
    pmpcfg_n[n*4 + 4].bits @
    pmpcfg_n[n*4 + 3].bits @
    pmpcfg_n[n*4 + 2].bits @
    pmpcfg_n[n*4 + 1].bits @
    pmpcfg_n[n*4 + 0].bits
  }
}

function pmpReadAddrReg(n : range(0, 63)) -> xlenbits = {
  let G = sys_pmp_grain;
  let match_type = pmpcfg_n[n][A];
  let addr = pmpaddr_n[n];

  match match_type[1] {
    bitone if G >= 2 => {
      // [G-2..0] read as all ones to form mask, therefore we need G-1 bits.
      let mask : xlenbits = zero_extend(ones(min(G - 1, xlen)));
      addr | mask
    },

    bitzero if G >= 1 => {
      // [G-1..0] read as all zeros to form mask, therefore we need G bits.
      let mask : xlenbits = zero_extend(ones(min(G , xlen)));
      addr & ~(mask)
    },

    _ => addr,
  }
}

/* Helpers to handle locked entries */
function pmpLocked(cfg: Pmpcfg_ent) -> bool =
   cfg[L] == 0b1

function pmpTORLocked(cfg: Pmpcfg_ent) -> bool =
   (cfg[L] == 0b1) & (pmpAddrMatchType_of_bits(cfg[A]) == TOR)

function pmpWriteCfg(n: range(0, 63), cfg: Pmpcfg_ent, v: bits(8)) -> Pmpcfg_ent =
  if pmpLocked(cfg) then cfg
  else {
    // Bits 5 and 6 are zero.
    let cfg = Mk_Pmpcfg_ent(v & 0x9f);

    // "The R, W, and X fields form a collective WARL field for which the combinations with R=0 and W=1 are reserved."
    // In this implementation if R=0 and W=1 then R, W and X are all set to 0.
    // This is the least risky option from a security perspective.
    let cfg = if cfg[W] == 0b1 & cfg[R] == 0b0 then [cfg with X = 0b0, W = 0b0, R = 0b0] else cfg;

    // "When G >= 1, the NA4 mode is not selectable."
    // In this implementation we set it to OFF if NA4 is selected.
    // This is the least risky option from a security perspective.
    let cfg = if sys_pmp_grain >= 1 & pmpAddrMatchType_of_bits(cfg[A]) == NA4
              then [cfg with A = pmpAddrMatchType_to_bits(OFF)]
              else cfg;

    cfg
  }

function pmpWriteCfgReg(n : range(0, 15), v : xlenbits) -> unit = {
  if xlen == 32
  then {
    foreach (i from 0 to 3) {
      let idx = n*4 + i;
      pmpcfg_n[idx]  = pmpWriteCfg(idx,  pmpcfg_n[idx],  v[8*i+7 .. 8*i]);
    }
  }
  else {
    assert(n % 2 == 0, "Unexpected pmp config reg write");
    foreach (i from 0 to 7) {
      let idx = n*4 + i;
      pmpcfg_n[idx]  = pmpWriteCfg(idx,  pmpcfg_n[idx],  v[8*i+7 .. 8*i]);
    }
  }
}

function pmpWriteAddr(locked: bool, tor_locked: bool, reg: xlenbits, v: xlenbits) -> xlenbits =
  if   xlen == 32
  then { if (locked | tor_locked) then reg else v }
  else { if (locked | tor_locked) then reg else zero_extend(v[53..0]) }

function pmpWriteAddrReg(n : range(0, 63), v : xlenbits) -> unit = {
  pmpaddr_n[n] = pmpWriteAddr(
    pmpLocked(pmpcfg_n[n]),
    if n + 1 < 64 then pmpTORLocked(pmpcfg_n[n + 1]) else false,
    pmpaddr_n[n],
    v,
  );
}

/* PMP CSRs */
mapping clause csr_name_map = 0x3A0  <-> "pmpcfg0"
mapping clause csr_name_map = 0x3A1  <-> "pmpcfg1"
mapping clause csr_name_map = 0x3A2  <-> "pmpcfg2"
mapping clause csr_name_map = 0x3A3  <-> "pmpcfg3"
mapping clause csr_name_map = 0x3A4  <-> "pmpcfg4"
mapping clause csr_name_map = 0x3A5  <-> "pmpcfg5"
mapping clause csr_name_map = 0x3A6  <-> "pmpcfg6"
mapping clause csr_name_map = 0x3A7  <-> "pmpcfg7"
mapping clause csr_name_map = 0x3A8  <-> "pmpcfg8"
mapping clause csr_name_map = 0x3A9  <-> "pmpcfg9"
mapping clause csr_name_map = 0x3AA  <-> "pmpcfg10"
mapping clause csr_name_map = 0x3AB  <-> "pmpcfg11"
mapping clause csr_name_map = 0x3AC  <-> "pmpcfg12"
mapping clause csr_name_map = 0x3AD  <-> "pmpcfg13"
mapping clause csr_name_map = 0x3AE  <-> "pmpcfg14"
mapping clause csr_name_map = 0x3AF  <-> "pmpcfg15"

mapping clause csr_name_map = 0x3B0  <-> "pmpaddr0"
mapping clause csr_name_map = 0x3B1  <-> "pmpaddr1"
mapping clause csr_name_map = 0x3B2  <-> "pmpaddr2"
mapping clause csr_name_map = 0x3B3  <-> "pmpaddr3"
mapping clause csr_name_map = 0x3B4  <-> "pmpaddr4"
mapping clause csr_name_map = 0x3B5  <-> "pmpaddr5"
mapping clause csr_name_map = 0x3B6  <-> "pmpaddr6"
mapping clause csr_name_map = 0x3B7  <-> "pmpaddr7"
mapping clause csr_name_map = 0x3B8  <-> "pmpaddr8"
mapping clause csr_name_map = 0x3B9  <-> "pmpaddr9"
mapping clause csr_name_map = 0x3BA  <-> "pmpaddr10"
mapping clause csr_name_map = 0x3BB  <-> "pmpaddr11"
mapping clause csr_name_map = 0x3BC  <-> "pmpaddr12"
mapping clause csr_name_map = 0x3BD  <-> "pmpaddr13"
mapping clause csr_name_map = 0x3BE  <-> "pmpaddr14"
mapping clause csr_name_map = 0x3BF  <-> "pmpaddr15"
mapping clause csr_name_map = 0x3C0  <-> "pmpaddr16"
mapping clause csr_name_map = 0x3C1  <-> "pmpaddr17"
mapping clause csr_name_map = 0x3C2  <-> "pmpaddr18"
mapping clause csr_name_map = 0x3C3  <-> "pmpaddr19"
mapping clause csr_name_map = 0x3C4  <-> "pmpaddr20"
mapping clause csr_name_map = 0x3C5  <-> "pmpaddr21"
mapping clause csr_name_map = 0x3C6  <-> "pmpaddr22"
mapping clause csr_name_map = 0x3C7  <-> "pmpaddr23"
mapping clause csr_name_map = 0x3C8  <-> "pmpaddr24"
mapping clause csr_name_map = 0x3C9  <-> "pmpaddr25"
mapping clause csr_name_map = 0x3CA  <-> "pmpaddr26"
mapping clause csr_name_map = 0x3CB  <-> "pmpaddr27"
mapping clause csr_name_map = 0x3CC  <-> "pmpaddr28"
mapping clause csr_name_map = 0x3CD  <-> "pmpaddr29"
mapping clause csr_name_map = 0x3CE  <-> "pmpaddr30"
mapping clause csr_name_map = 0x3CF  <-> "pmpaddr31"
mapping clause csr_name_map = 0x3D0  <-> "pmpaddr32"
mapping clause csr_name_map = 0x3D1  <-> "pmpaddr33"
mapping clause csr_name_map = 0x3D2  <-> "pmpaddr34"
mapping clause csr_name_map = 0x3D3  <-> "pmpaddr35"
mapping clause csr_name_map = 0x3D4  <-> "pmpaddr36"
mapping clause csr_name_map = 0x3D5  <-> "pmpaddr37"
mapping clause csr_name_map = 0x3D6  <-> "pmpaddr38"
mapping clause csr_name_map = 0x3D7  <-> "pmpaddr39"
mapping clause csr_name_map = 0x3D8  <-> "pmpaddr40"
mapping clause csr_name_map = 0x3D9  <-> "pmpaddr41"
mapping clause csr_name_map = 0x3DA  <-> "pmpaddr42"
mapping clause csr_name_map = 0x3DB  <-> "pmpaddr43"
mapping clause csr_name_map = 0x3DC  <-> "pmpaddr44"
mapping clause csr_name_map = 0x3DD  <-> "pmpaddr45"
mapping clause csr_name_map = 0x3DE  <-> "pmpaddr46"
mapping clause csr_name_map = 0x3DF  <-> "pmpaddr47"
mapping clause csr_name_map = 0x3E0  <-> "pmpaddr48"
mapping clause csr_name_map = 0x3E1  <-> "pmpaddr49"
mapping clause csr_name_map = 0x3E2  <-> "pmpaddr50"
mapping clause csr_name_map = 0x3E3  <-> "pmpaddr51"
mapping clause csr_name_map = 0x3E4  <-> "pmpaddr52"
mapping clause csr_name_map = 0x3E5  <-> "pmpaddr53"
mapping clause csr_name_map = 0x3E6  <-> "pmpaddr54"
mapping clause csr_name_map = 0x3E7  <-> "pmpaddr55"
mapping clause csr_name_map = 0x3E8  <-> "pmpaddr56"
mapping clause csr_name_map = 0x3E9  <-> "pmpaddr57"
mapping clause csr_name_map = 0x3EA  <-> "pmpaddr58"
mapping clause csr_name_map = 0x3EB  <-> "pmpaddr59"
mapping clause csr_name_map = 0x3EC  <-> "pmpaddr60"
mapping clause csr_name_map = 0x3ED  <-> "pmpaddr61"
mapping clause csr_name_map = 0x3EE  <-> "pmpaddr62"
mapping clause csr_name_map = 0x3EF  <-> "pmpaddr63"

mapping clause csr_name_map = 0x1F2  <-> "mpmpdeleg"  // allows an implementation to hardwire the PMP/SPMP split if desired

// mpmpdeleg
function clause is_CSR_defined(0x1F2) = true
function clause read_CSR(0x1F2) = zero_extend(mpmpdeleg.bits)
function clause write_CSR(0x1F2, value) = {
  let new_pmpnum = unsigned(value[6 .. 0]);
  let current_pmpnum = getPmpNum();
  
  // Check if MML (Machine Mode Lockdown) bit is set
  if mseccfg[MML] == 0b1 then {
    // When MML is set, pmpnum is locked and cannot be changed
    zero_extend(mpmpdeleg.bits)
  }
  // Check if new value is valid (alignment and range)
  else if ~(isValidPmpNum(new_pmpnum)) then {
    zero_extend(mpmpdeleg.bits)
  }
  // Check if any PMP entries in affected range are locked
  else if new_pmpnum > current_pmpnum then {
    // Moving resources from PMP to SPMP: check if any affected PMP entries are locked
    if anyPmpLocked(new_pmpnum, current_pmpnum) then {
      zero_extend(mpmpdeleg.bits)
    } else {
      mpmpdeleg = [mpmpdeleg with pmpnum = value[6 .. 0]];
      zero_extend(mpmpdeleg.bits)
    }
  } else if new_pmpnum < current_pmpnum then {
    // Moving resources from SPMP to PMP: check if any affected SPMP entries are locked
    if anyPmpLocked(new_pmpnum, current_pmpnum) then {
      zero_extend(mpmpdeleg.bits)
    } else {
      mpmpdeleg = [mpmpdeleg with pmpnum = value[6 .. 0]];
      zero_extend(mpmpdeleg.bits)
    }
  } else {
    // No change in pmpnum
    zero_extend(mpmpdeleg.bits)
  }
}

// pmpcfgN
function clause is_CSR_defined(0x3A) @ idx : bits(4) = {
  let cfg_idx = unsigned(idx);
  let max_entries = getPmpNum();
  let first_entry = cfg_idx * (if xlen == 32 then 4 else 8);
  (idx[0] == bitzero | xlen == 32) & (first_entry < max_entries)
}
function clause read_CSR(0x3A @ idx : bits(4) if idx[0] == bitzero | xlen == 32) = pmpReadCfgReg(unsigned(idx))
function clause write_CSR((0x3A @ idx : bits(4), value) if idx[0] == bitzero | xlen == 32) = {
  let idx = unsigned(idx);
  pmpWriteCfgReg(idx, value);
  pmpReadCfgReg(idx)
}

// pmpaddrN. Unfortunately the PMP index does not nicely align with the CSR index bits.
function clause is_CSR_defined(0x3B) @ idx : bits(4) = {
  let addr_idx = unsigned(0b00 @ idx);
  addr_idx < getPmpNum()
}
function clause is_CSR_defined(0x3C) @ idx : bits(4) = {
  let addr_idx = unsigned(0b01 @ idx);
  addr_idx < getPmpNum()
}
function clause is_CSR_defined(0x3D) @ idx : bits(4) = {
  let addr_idx = unsigned(0b10 @ idx);
  addr_idx < getPmpNum()
}
function clause is_CSR_defined(0x3E) @ idx : bits(4) = {
  let addr_idx = unsigned(0b11 @ idx);
  addr_idx < getPmpNum()
}

function clause read_CSR(0x3B @ idx : bits(4)) = pmpReadAddrReg(unsigned(0b00 @ idx))
function clause read_CSR(0x3C @ idx : bits(4)) = pmpReadAddrReg(unsigned(0b01 @ idx))
function clause read_CSR(0x3D @ idx : bits(4)) = pmpReadAddrReg(unsigned(0b10 @ idx))
function clause read_CSR(0x3E @ idx : bits(4)) = pmpReadAddrReg(unsigned(0b11 @ idx))

function clause write_CSR(0x3B @ idx : bits(4), value) = { let idx = unsigned(0b00 @ idx); pmpWriteAddrReg(idx, value); pmpReadAddrReg(idx) }
function clause write_CSR(0x3C @ idx : bits(4), value) = { let idx = unsigned(0b01 @ idx); pmpWriteAddrReg(idx, value); pmpReadAddrReg(idx) }
function clause write_CSR(0x3D @ idx : bits(4), value) = { let idx = unsigned(0b10 @ idx); pmpWriteAddrReg(idx, value); pmpReadAddrReg(idx) }
function clause write_CSR(0x3E @ idx : bits(4), value) = { let idx = unsigned(0b11 @ idx); pmpWriteAddrReg(idx, value); pmpReadAddrReg(idx) }
