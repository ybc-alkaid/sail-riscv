/*=======================================================================================*/
/*  SPMP (Supervisor Mode Physical Memory Protection) Register Definitions              */
/*                                                                                       */
/*  This module implements the SPMP CSR interface as specified in .    */
/*  SPMP provides 64 protection entries with configuration and address registers.       */
/*                                                                                       */
/*  CSR Address Space ( Section 2.1):                                   */
/*    0x1A0-0x1AF: spmpcfg0-spmpcfg15   (Configuration registers)                       */
/*    0x1B0-0x1EF: spmpaddr0-spmpaddr63 (Address registers)                             */
/*                                                                                       */
/*  Privilege Level: Supervisor (0x1XX address space)                                   */
/*                                                                                       */
/*  Lock Bit (L) Access Control Rules:                                                  */
/*    - L bit is only accessible to M-mode for writes                                   */
/*    - M-mode: Can read/write L bit and modify locked entries                          */
/*    - S-mode: Cannot modify locked entries (writes ignored when L=1)                 */
/*    - L bit is not sticky - can only be reset by M-mode                              */
/*    - Setting L=1 locks entry even when A=OFF                                        */
/*    - For locked TOR entries, S-mode writes to previous addr register ignored        */
/*=======================================================================================*/

/* SPMP platform configuration parameters.
 * These values are typically set at build time based on platform capabilities. */
let sys_spmp_enabled : bool = config memory.spmp.enabled  // Platform SPMP support
let sys_spmp_count : nat = config memory.spmp.count       // Number of SPMP entries

/*=======================================================================================*/
/*  SPMP Configuration Register CSR Name Mappings (0x1A0-0x1AF)                        */
/*                                                                                       */
/*  Each spmpcfg register contains configuration for multiple SPMP entries:             */
/*    - RV32: 4 entries per register (8 bits each)                                      */
/*    - RV64: 8 entries per register (8 bits each)                                      */
/*                                                                                       */
/*  Configuration bits per entry ( Section 2.2):                       */
/*    [7]: L - Lock bit (prevents further modifications when set)                       */
/*    [6]: S - Supervisor/User mode shared permission management (Section 2.3)         */
/*    [5]: Reserved (WPRI - Write Preserve, Read Ignore)                               */
/*    [4:3]: A - Address matching mode (OFF/TOR/NA4/NAPOT)                             */
/*    [2]: X - Execute permission                                                       */
/*    [1]: W - Write permission                                                         */
/*    [0]: R - Read permission                                                          */
/*=======================================================================================*/
/*  SPMP CSR Name Mappings - REMOVED                                                    */
/*                                                                                       */
/*  SPMP CSRs are now accessed indirectly through siselect/sireg interface:            */
/*  - siselect[11:0] = entry_index (0-63)                                              */
/*  - sireg  = spmpaddr[entry_index]                                                   */
/*  - sireg2 = spmpcfg[entry_index]                                                    */
/*                                                                                       */
/*  Direct CSR access via 0x1A0-0x1EF addresses is disabled in favor of               */
/*  indirect access for better performance and context switching.                      */
/*=======================================================================================*/
/*
// SPMP configuration registers (0x1A0-0x1AF) - REMOVED
mapping clause csr_name_map = 0x1A0  <-> "spmpcfg0"   
mapping clause csr_name_map = 0x1A1  <-> "spmpcfg1"   
mapping clause csr_name_map = 0x1A2  <-> "spmpcfg2"   
mapping clause csr_name_map = 0x1A3  <-> "spmpcfg3"   
mapping clause csr_name_map = 0x1A4  <-> "spmpcfg4"   
mapping clause csr_name_map = 0x1A5  <-> "spmpcfg5"   
mapping clause csr_name_map = 0x1A6  <-> "spmpcfg6"   
mapping clause csr_name_map = 0x1A7  <-> "spmpcfg7"   
mapping clause csr_name_map = 0x1A8  <-> "spmpcfg8"   
mapping clause csr_name_map = 0x1A9  <-> "spmpcfg9"   
mapping clause csr_name_map = 0x1AA  <-> "spmpcfg10"  
mapping clause csr_name_map = 0x1AB  <-> "spmpcfg11"  
mapping clause csr_name_map = 0x1AC  <-> "spmpcfg12"  
mapping clause csr_name_map = 0x1AD  <-> "spmpcfg13"  
mapping clause csr_name_map = 0x1AE  <-> "spmpcfg14"  
mapping clause csr_name_map = 0x1AF  <-> "spmpcfg15"  
*/

/*=======================================================================================*/
/*  SPMP Address Register CSR Name Mappings (0x1B0-0x1EF)                              */
/*                                                                                       */
/*  Each spmpaddr register contains one address value ( Section 2.2):  */
/*    - Contains bits [XLEN-1:2] of the address (word-aligned)                          */
/*    - Interpretation depends on address matching mode in corresponding spmpcfg        */
/*    - TOR: Top address of range [prev_addr*4, addr*4)                                 */
/*    - NA4/NAPOT: Base address with mode-specific encoding                             */
/*=======================================================================================*/

/*
// SPMP address registers (0x1B0-0x1EF) - REMOVED
mapping clause csr_name_map = 0x1B0  <-> "spmpaddr0"   
mapping clause csr_name_map = 0x1B1  <-> "spmpaddr1"   
mapping clause csr_name_map = 0x1B2  <-> "spmpaddr2"   
mapping clause csr_name_map = 0x1B3  <-> "spmpaddr3"   
mapping clause csr_name_map = 0x1B4  <-> "spmpaddr4"   
mapping clause csr_name_map = 0x1B5  <-> "spmpaddr5"   
mapping clause csr_name_map = 0x1B6  <-> "spmpaddr6"   
mapping clause csr_name_map = 0x1B7  <-> "spmpaddr7"   
mapping clause csr_name_map = 0x1B8  <-> "spmpaddr8"   
mapping clause csr_name_map = 0x1B9  <-> "spmpaddr9"   
mapping clause csr_name_map = 0x1BA  <-> "spmpaddr10"  
mapping clause csr_name_map = 0x1BB  <-> "spmpaddr11"  
mapping clause csr_name_map = 0x1BC  <-> "spmpaddr12"  
mapping clause csr_name_map = 0x1BD  <-> "spmpaddr13"  
mapping clause csr_name_map = 0x1BE  <-> "spmpaddr14"  
mapping clause csr_name_map = 0x1BF  <-> "spmpaddr15"  
mapping clause csr_name_map = 0x1C0  <-> "spmpaddr16"  
mapping clause csr_name_map = 0x1C1  <-> "spmpaddr17"  
mapping clause csr_name_map = 0x1C2  <-> "spmpaddr18"  
mapping clause csr_name_map = 0x1C3  <-> "spmpaddr19"  
mapping clause csr_name_map = 0x1C4  <-> "spmpaddr20"  
mapping clause csr_name_map = 0x1C5  <-> "spmpaddr21"  
mapping clause csr_name_map = 0x1C6  <-> "spmpaddr22"  
mapping clause csr_name_map = 0x1C7  <-> "spmpaddr23"  
mapping clause csr_name_map = 0x1C8  <-> "spmpaddr24"  
mapping clause csr_name_map = 0x1C9  <-> "spmpaddr25"  
mapping clause csr_name_map = 0x1CA  <-> "spmpaddr26"  
mapping clause csr_name_map = 0x1CB  <-> "spmpaddr27"
mapping clause csr_name_map = 0x1CC  <-> "spmpaddr28"
mapping clause csr_name_map = 0x1CD  <-> "spmpaddr29"
mapping clause csr_name_map = 0x1CE  <-> "spmpaddr30"
mapping clause csr_name_map = 0x1CF  <-> "spmpaddr31"
mapping clause csr_name_map = 0x1D0  <-> "spmpaddr32"
mapping clause csr_name_map = 0x1D1  <-> "spmpaddr33"
mapping clause csr_name_map = 0x1D2  <-> "spmpaddr34"
mapping clause csr_name_map = 0x1D3  <-> "spmpaddr35"
mapping clause csr_name_map = 0x1D4  <-> "spmpaddr36"
mapping clause csr_name_map = 0x1D5  <-> "spmpaddr37"
mapping clause csr_name_map = 0x1D6  <-> "spmpaddr38"
mapping clause csr_name_map = 0x1D7  <-> "spmpaddr39"
mapping clause csr_name_map = 0x1D8  <-> "spmpaddr40"
mapping clause csr_name_map = 0x1D9  <-> "spmpaddr41"
mapping clause csr_name_map = 0x1DA  <-> "spmpaddr42"
mapping clause csr_name_map = 0x1DB  <-> "spmpaddr43"
mapping clause csr_name_map = 0x1DC  <-> "spmpaddr44"
mapping clause csr_name_map = 0x1DD  <-> "spmpaddr45"
mapping clause csr_name_map = 0x1DE  <-> "spmpaddr46"
mapping clause csr_name_map = 0x1DF  <-> "spmpaddr47"
mapping clause csr_name_map = 0x1E0  <-> "spmpaddr48"
mapping clause csr_name_map = 0x1E1  <-> "spmpaddr49"
mapping clause csr_name_map = 0x1E2  <-> "spmpaddr50"
mapping clause csr_name_map = 0x1E3  <-> "spmpaddr51"
mapping clause csr_name_map = 0x1E4  <-> "spmpaddr52"
mapping clause csr_name_map = 0x1E5  <-> "spmpaddr53"
mapping clause csr_name_map = 0x1E6  <-> "spmpaddr54"
mapping clause csr_name_map = 0x1E7  <-> "spmpaddr55"
mapping clause csr_name_map = 0x1E8  <-> "spmpaddr56"
mapping clause csr_name_map = 0x1E9  <-> "spmpaddr57"
mapping clause csr_name_map = 0x1EA  <-> "spmpaddr58"
mapping clause csr_name_map = 0x1EB  <-> "spmpaddr59"
mapping clause csr_name_map = 0x1EC  <-> "spmpaddr60"
mapping clause csr_name_map = 0x1ED  <-> "spmpaddr61"
mapping clause csr_name_map = 0x1EE  <-> "spmpaddr62"
mapping clause csr_name_map = 0x1EF  <-> "spmpaddr63"
*/

mapping clause csr_name_map = 0x1F0  <-> "spmpswitch" // SPMP domain switch register
mapping clause csr_name_map = 0x1F1  <-> "spmpswitchh" // SPMP domain switch register high (RV32 only)
// mapping clause csr_name_map = 0x1F2  <-> "mpmpdeleg"  // allows an implementation to hardwire the PMP/SPMP split if desired

/*=======================================================================================*/
/*  SPMP Context Switching Optimization (Section 2.8)                                  */
/*                                                                                       */
/*  The spmpswitch registers provide context switching optimization by allowing         */
/*  software to activate/deactivate SPMP entries without modifying configuration.      */
/*                                                                                       */
/*  Register Layout:                                                                     */
/*    - RV32: spmpswitch (entries 0-31) + spmpswitchh (entries 32-63)                  */
/*    - RV64: spmpswitch (entries 0-63)                                                 */
/*                                                                                       */
/*  Activation Rule:                                                                     */
/*    An entry is active only when: spmpswitch[i] & (spmp[i]cfg.A != OFF)              */
/*                                                                                       */
/*  Special Cases:                                                                       */
/*    - When spmpswitch[i] == 0 and spmp[i]cfg.L == 1, entry i remains enabled        */
/*    - TOR entries match regardless of spmpswitch[i-1] value                          */
/*    - spmpswitch registers must be cleared on reset                                   */
/*=======================================================================================*/

/* SPMP switch registers - control activation of SPMP entries */
register spmpswitch : xlenbits
register spmpswitchh : bits(32)  // Only used in RV32

/* SPMP configuration entries */

/* Reuse PmpAddrMatchType */
// enum PmpAddrMatchType = {OFF, TOR, NA4, NAPOT}

val spmpAddrMatchType_of_bits : bits(2) -> PmpAddrMatchType
function spmpAddrMatchType_of_bits(bs) = {
  match bs {
    0b00 => OFF,
    0b01 => TOR,
    0b10 => NA4,
    0b11 => NAPOT
  }
}

val spmpAddrMatchType_to_bits : PmpAddrMatchType -> bits(2)
function spmpAddrMatchType_to_bits(bs) = {
  match bs {
    OFF   => 0b00,
    TOR   => 0b01,
    NA4   => 0b10,
    NAPOT => 0b11
  }
}

bitfield Spmpcfg_ent : bits(16) = {
  /* Bits 15-10: Reserved for future use */
  
  SHARED : 9,   /* SHARED bit - marks a Shared-Region rule (WARL) */
  U : 8,        /* U bit - marks U-mode-only when set, S-mode-only when unset (WARL) */
  L : 7,        /* Lock bit - prevents further modifications when set (WARL) */
  
  /* Bits 6-5: Reserved for future use */
  
  A : 4 .. 3,   /* Address matching mode (OFF/TOR/NA4/NAPOT) (WARL) */

  /* Memory access permissions (WARL) */
  X : 2,        /* Execute permission */
  W : 1,        /* Write permission */
  R : 0         /* Read permission */
}

register spmpcfg_n : vector(64, Spmpcfg_ent)
register spmpaddr_n : vector(64, xlenbits)

/*=======================================================================================*/
/*  SPMP Indirect CSR Access Functions                                                  */
/*                                                                                       */
/*  These functions implement the indirect CSR access mechanism for SPMP:               */
/*  - siselect[11:0] = entry_index (0-63)                                              */
/*  - sireg  = spmpaddr[entry_index] (indirect address access)                         */
/*  - sireg2 = spmpcfg[entry_index]  (indirect configuration access)                   */
/*                                                                                       */
/*  Access Rules:                                                                        */
/*  - S-mode can set spmp[i]cfg.L to lock an SPMP entry                               */
/*  - When spmp[i]cfg.L is set, SPMP writes via siselect are ignored                   */
/*  - Only M-mode access via miselect can reset spmp[i]cfg.L                          */
/*=======================================================================================*/

// enum IregType = { Mireg, Sireg }

/* Indirect CSR access functions - these will be used by the SPMP module */
/* to access SPMP registers instead of direct array access */
/* Get valid SPMP entry range based on delegation */
function getSpmpValidRange() -> (nat, nat) = {
  let pmp_count = getPmpNum();           
  let total_resources = 64;              
  let spmp_start = pmp_count;             
  let spmp_count = total_resources - pmp_count;  
  // Ensure we don't return negative values for nat type
  if spmp_count <= 0 then (0, 0)
  else (spmp_start, total_resources - 1) // [pmpnum, 63] - hardware indices
}

/* Check if SPMP entry index is valid for current privilege */
function spmpCheckEntryAccess(entry_idx: range(0, 4095), priv: Privilege) -> bool = {
  let (min_idx, max_idx) = getSpmpValidRange();
  (entry_idx >= min_idx) & (entry_idx <= max_idx)
}

/* Read SPMP address register via indirect access */
function spmp_read_addr_indirect(entry_idx: range(0, 4095)) -> xlenbits = {
  if spmpCheckEntryAccess(entry_idx, cur_privilege) then {
    // entry_idx is a hardware index (pmpnum to 63)
    if entry_idx < 64 then {
      let old_siselect = read_CSR(0x150);
      let _ = write_CSR(0x150, zero_extend(to_bits(12, entry_idx)));
      let result = read_CSR(0x151);
      let _ = write_CSR(0x150, old_siselect);
      result
    } else {
      zeros()
    }
  } else {
    zeros()
  }
}

/* Enhanced SPMP configuration read with range checking */
function spmp_read_cfg_indirect(entry_idx: range(0, 4095)) -> Spmpcfg_ent = {
  if spmpCheckEntryAccess(entry_idx, cur_privilege) then {
    // entry_idx is a hardware index (pmpnum to 63)
    if entry_idx < 64 then {
      let old_siselect = read_CSR(0x150);
      let _ = write_CSR(0x150, zero_extend(to_bits(12, entry_idx)));
      let result = read_CSR(0x152);
      let _ = write_CSR(0x150, old_siselect);
      Mk_Spmpcfg_ent(result[15..0])  // Read 16 bits for SPMP config
    } else {
      Mk_Spmpcfg_ent(0x0000)  // 16-bit zero
    }
  } else {
    Mk_Spmpcfg_ent(0x0000)  // 16-bit zero
  }
}

/* Write SPMP address register via indirect access */
function spmp_write_addr_indirect(entry_idx: range(0, 4095), value: xlenbits) -> unit = {
  if spmpCheckEntryAccess(entry_idx, cur_privilege) then {
    // entry_idx is a hardware index (pmpnum to 63)
    if entry_idx < 64 then {
      let old_siselect = read_CSR(0x150);
      let _ = write_CSR(0x150, zero_extend(to_bits(12, entry_idx)));
      let _ = write_CSR(0x151, value);
      let _ = write_CSR(0x150, old_siselect);
    }
  }
}

/* Write SPMP configuration register via indirect access */
function spmp_write_cfg_indirect(entry_idx: range(0, 4095), cfg: Spmpcfg_ent) -> unit = {
  if spmpCheckEntryAccess(entry_idx, cur_privilege) then {
    // entry_idx is a hardware index (pmpnum to 63)
    if entry_idx < 64 then {
      let old_siselect = read_CSR(0x150);
      let _ = write_CSR(0x150, zero_extend(to_bits(12, entry_idx)));
      let _ = write_CSR(0x152, zero_extend(cfg.bits));
      let _ = write_CSR(0x150, old_siselect);
    }
  }
}

/* M-mode version with same range checking for consistency */
function spmp_mmode_write_cfg_indirect(entry_idx: range(0, 4095), cfg: Spmpcfg_ent) -> unit = {
  if spmpCheckEntryAccess(entry_idx, Machine) then {
    // entry_idx is a hardware index (pmpnum to 63)
    if entry_idx < 64 then {
      let old_miselect = read_CSR(0x350);
      let _ = write_CSR(0x350, zero_extend(to_bits(12, entry_idx)));
      let _ = write_CSR(0x352, zero_extend(cfg.bits));
      let _ = write_CSR(0x350, old_miselect);
    }
  }
}

/* M-mode configuration register read via miselect interface */
function spmp_mmode_read_cfg_indirect(entry_idx: range(0, 4095)) -> Spmpcfg_ent = {
  if spmpCheckEntryAccess(entry_idx, Machine) then {
    // entry_idx is a hardware index (pmpnum to 63)
    if entry_idx < 64 then {
      let old_miselect = read_CSR(0x350);
      let _ = write_CSR(0x350, zero_extend(to_bits(12, entry_idx)));
      let result = read_CSR(0x352);  // mireg2 (0x352) for configuration access
      let _ = write_CSR(0x350, old_miselect);
      Mk_Spmpcfg_ent(result[15..0])  // Read 16 bits for SPMP config
    } else {
      Mk_Spmpcfg_ent(0x0000)  // 16-bit zero
    }
  } else {
    Mk_Spmpcfg_ent(0x0000)  // 16-bit zero
  }
}

/* M-mode address register write via miselect interface */
function spmp_mmode_write_addr_indirect(entry_idx: range(0, 4095), value: xlenbits) -> unit = {
  if spmpCheckEntryAccess(entry_idx, Machine) then {
    let hw_idx = spmpSwToHwIndex(entry_idx);
    if hw_idx < 64 then {
      let old_miselect = read_CSR(0x350);
      let _ = write_CSR(0x350, zero_extend(to_bits(12, entry_idx)));
      let _ = write_CSR(0x351, value);  // mireg (0x351) for address access
      let _ = write_CSR(0x350, old_miselect);
    }
  }
}

/* M-mode address register read via miselect interface */
function spmp_mmode_read_addr_indirect(entry_idx: range(0, 4095)) -> xlenbits = {
  if spmpCheckEntryAccess(entry_idx, Machine) then {
    let hw_idx = spmpSwToHwIndex(entry_idx);
    if hw_idx < 64 then {
      let old_miselect = read_CSR(0x350);
      let _ = write_CSR(0x350, zero_extend(to_bits(12, entry_idx)));
      let result = read_CSR(0x351);  // mireg (0x351) for address access
      let _ = write_CSR(0x350, old_miselect);
      result
    } else {
      
      zeros()
    }
  } else {
    
    zeros()
  }
}


/* Packing and unpacking spmpcfg regs for xlen-width accesses */

function spmpReadCfgReg(n : range(0, 15)) -> xlenbits = {
  let spmp_start = getPmpNum();  // First SPMP hardware index
  if xlen == 32
  then {
    // RV32: Each register contains 2 entries (16 bits each)
    let base_idx = n * 2;
    let hw_idx0 = spmp_start + base_idx + 0;
    let hw_idx1 = spmp_start + base_idx + 1;
    // Ensure indices are within bounds
    if hw_idx1 < 64 & hw_idx0 < 64 then {
      spmp_read_cfg_indirect(hw_idx1).bits @
      spmp_read_cfg_indirect(hw_idx0).bits
    } else {
      zeros()
    }
  }
  else {
    // RV64: Each register contains 4 entries (16 bits each)
    assert(n % 2 == 0, "Unexpected spmp config reg read");
    let base_idx = n * 2;  // Adjusted for 16-bit entries
    let hw_idx0 = spmp_start + base_idx + 0;
    let hw_idx1 = spmp_start + base_idx + 1;
    let hw_idx2 = spmp_start + base_idx + 2;
    let hw_idx3 = spmp_start + base_idx + 3;
    // Ensure indices are within bounds
    if hw_idx3 < 64 & hw_idx2 < 64 & hw_idx1 < 64 & hw_idx0 < 64 then {
      spmp_read_cfg_indirect(hw_idx3).bits @
      spmp_read_cfg_indirect(hw_idx2).bits @
      spmp_read_cfg_indirect(hw_idx1).bits @
      spmp_read_cfg_indirect(hw_idx0).bits
    } else {
      zeros()
    }
  }
}

/* Helpers to handle locked entries */
function spmpLocked(cfg: Spmpcfg_ent) -> bool =
   cfg[L] == 0b1

function spmpTORLocked(cfg: Spmpcfg_ent) -> bool =
   (cfg[L] == 0b1) & (spmpAddrMatchType_of_bits(cfg[A]) == TOR)

/* Check if SPMP entry write is allowed based on privilege level and lock status.
 * 
 * L bit access control rules:
 * - M-mode: Can always read/write L bit and modify locked entries
 * - S-mode: Cannot modify locked entries (writes are ignored when L=1)
 * - The L bit is only accessible to M-mode for writes
 */
function spmpWriteCfg(n: range(0, 63), cfg: Spmpcfg_ent, v: bits(16), priv: Privilege) -> Spmpcfg_ent = {
  // Check if entry is locked and current privilege
  let is_locked = spmpLocked(cfg);
  let is_machine_mode = (priv == Machine);
  
  // If locked and not in M-mode, ignore write completely
  if is_locked & not(is_machine_mode) then cfg
  else {
    // Create new configuration from input value
    // Preserve reserved bits [15:10], [6:5] (WPRI) and allow modification of other fields  
    let reserved_mask = 0xFC60;  // bits 15:10 and 6:5
    let writable_mask = 0x039F;  // bits 9:7 and 4:0
    let new_cfg = Mk_Spmpcfg_ent((v & writable_mask) | (cfg.bits & reserved_mask));
    
    // L bit access control: 
    // - M-mode: Can freely modify L bit (0→1 or 1→0)
    // - S-mode: Can only set L bit (0→1), cannot clear it (1→0)
    let new_cfg = if not(is_machine_mode) then {
      // S-mode can only set L bit, not clear it
      let current_L = cfg[L];
      let requested_L = new_cfg[L];
      // Allow 0→1 transition, deny 1→0 transition
      let final_L = if current_L == 0b1 then 0b1 else requested_L;
      [new_cfg with L = final_L]
    } else new_cfg;

    // "The R, W, and X fields form a collective WARL field for which the combinations with R=0 and W=1 are reserved."
    // In this implementation if R=0 and W=1 then R, W and X are all set to 0.
    // This is the least risky option from a security perspective.
    let new_cfg = if new_cfg[W] == 0b1 & new_cfg[R] == 0b0 then [new_cfg with X = 0b0, W = 0b0, R = 0b0] else new_cfg;

    new_cfg
  }
}

function spmpWriteCfgReg(n : range(0, 15), v : xlenbits) -> unit = {
  let spmp_start = getPmpNum();  // First SPMP hardware index
  if xlen == 32
  then {
    // RV32: Each register contains 2 entries (16 bits each)
    foreach (i from 0 to 1) {
      let hw_idx = spmp_start + n*2 + i;
      if hw_idx < 64 then {
        let current_cfg = spmp_read_cfg_indirect(hw_idx);
        let new_cfg = spmpWriteCfg(hw_idx, current_cfg, v[16*i+15 .. 16*i], cur_privilege);
        spmp_write_cfg_indirect(hw_idx, new_cfg);
      }
    }
  }
  else {
    // RV64: Each register contains 4 entries (16 bits each)
    assert(n % 2 == 0, "Unexpected spmp config reg write");
    foreach (i from 0 to 3) {
      let hw_idx = spmp_start + n*2 + i;  // Adjusted for 16-bit entries
      if hw_idx < 64 then {
        let current_cfg = spmp_read_cfg_indirect(hw_idx);
        let new_cfg = spmpWriteCfg(hw_idx, current_cfg, v[16*i+15 .. 16*i], cur_privilege);
        spmp_write_cfg_indirect(hw_idx, new_cfg);
      }
    }
  }
}

/* SPMP address register write with privilege-aware locking.
 * 
 * Address register write rules:
 * - M-mode: Can always write to address registers, even for locked entries
 * - S-mode: Cannot write to address registers of locked entries
 * - S-mode: Cannot write to spmpaddr[i-1] if spmp[i]cfg is locked and A=TOR
 */
function spmpWriteAddr(locked: bool, tor_locked: bool, reg: xlenbits, v: xlenbits, priv: Privilege) -> xlenbits = {
  let is_machine_mode = (priv == Machine);
  
  if xlen == 32
  then { 
    if (locked | tor_locked) & not(is_machine_mode) then reg else v 
  }
  else { 
    if (locked | tor_locked) & not(is_machine_mode) then reg else zero_extend(v[53..0]) 
  }
}

function spmpWriteAddrReg(n : range(0, 63), v : xlenbits) -> unit = {
  // Get current privilege for L bit access control
  let priv = cur_privilege;
  
  let current_cfg = spmp_read_cfg_indirect(n);
  let next_cfg = if n + 1 < 64 then spmp_read_cfg_indirect(n + 1) else Mk_Spmpcfg_ent(0x0000);
  let current_addr = spmp_read_addr_indirect(n);
  
  let new_addr = spmpWriteAddr(
    spmpLocked(current_cfg),
    if n + 1 < 64 then spmpTORLocked(next_cfg) else false,
    current_addr,
    v,
    priv
  );
  
  spmp_write_addr_indirect(n, new_addr);
}


/*=======================================================================================*/
// spmpswitch - SPMP domain switch register (RV64 and RV32)
function clause is_CSR_defined(0x1F0) = sys_spmp_enabled
function clause read_CSR(0x1F0) = spmpswitch
function clause write_CSR(0x1F0, value) = {
  if cur_privilege == Machine then {
    // M-mode can modify all switch bits
    spmpswitch = value;
  } else {
    // S-mode cannot modify switch bits for locked entries
    let current_switch = spmpswitch;
    var new_switch = current_switch;
    
    // Check each bit individually for RV64
    if xlen == 64 then {
      foreach (i from 0 to 63) {
        let cfg = spmp_read_cfg_indirect(i);
        if not(spmpLocked(cfg)) then {
          // Only modify non-locked entries
          let new_bit = value[i];
          new_switch = [new_switch with i = new_bit];
        }
      }
    } else {
      // RV32: Only check bits 0-31 for spmpswitch
      foreach (i from 0 to 31) {
        let cfg = spmp_read_cfg_indirect(i);
        if not(spmpLocked(cfg)) then {
          let new_bit = value[i];
          new_switch = [new_switch with i = new_bit];
        }
      }
    };
    
    spmpswitch = new_switch;
  };
  spmpswitch
}

// spmpswitchh - SPMP domain switch register high (RV32 only)
function clause is_CSR_defined(0x1F1) = sys_spmp_enabled & (xlen == 32)
function clause read_CSR(0x1F1) = {
  if xlen == 32
  then zero_extend(spmpswitchh)
  else zero_extend(0x0)
}
function clause write_CSR(0x1F1, value) = {
  if xlen == 32
  then {
    spmpswitchh = value[31..0];
    zero_extend(spmpswitchh)
  }
  else zero_extend(0x0)
}

/* Get the effective switch register value for 64-bit view */
function spmpGetFullSwitchReg() -> bits(64) = {
  if xlen == 32
  then spmpswitchh @ spmpswitch[31..0]
  else zero_extend(spmpswitch)
}

/* Initialize SPMP switch registers on reset */
function spmpSwitchReset() -> unit = {
  spmpswitch = zero_extend(0x0);
  spmpswitchh = 0x00000000;
}

/* SPMP CSRs - Direct access removed, now using indirect access via siselect/sireg */

/*
// spmpcfgN - REMOVED (now accessed via siselect/sireg2)
function clause is_CSR_defined(0x1A) @ idx : bits(4) = {
  let cfg_idx = unsigned(idx);
  let spmp_start = getPmpNum();  // First SPMP hardware index
  let first_entry = spmp_start + cfg_idx * (if xlen == 32 then 4 else 8);
  sys_spmp_enabled & (idx[0] == bitzero | xlen == 32) & (first_entry < 64)
}
function clause read_CSR(0x1A @ idx : bits(4) if idx[0] == bitzero | xlen == 32) = spmpReadCfgReg(unsigned(idx))
function clause write_CSR((0x1A @ idx : bits(4), value) if idx[0] == bitzero | xlen == 32) = {
  let idx = unsigned(idx);
  spmpWriteCfgReg(idx, value);
  spmpReadCfgReg(idx)
}

// spmpaddrN - REMOVED (now accessed via siselect/sireg)
function clause is_CSR_defined(0x1B) @ idx : bits(4) = {
  let spmp_start = getPmpNum();
  let addr_idx = spmp_start + unsigned(0b00 @ idx);
  sys_spmp_enabled & (addr_idx < 64)
}
function clause is_CSR_defined(0x1C) @ idx : bits(4) = {
  let spmp_start = getPmpNum();
  let addr_idx = spmp_start + unsigned(0b01 @ idx);
  sys_spmp_enabled & (addr_idx < 64)
}
function clause is_CSR_defined(0x1D) @ idx : bits(4) = {
  let spmp_start = getPmpNum();
  let addr_idx = spmp_start + unsigned(0b10 @ idx);
  sys_spmp_enabled & (addr_idx < 64)
}
function clause is_CSR_defined(0x1E) @ idx : bits(4) = {
  let spmp_start = getPmpNum();
  let addr_idx = spmp_start + unsigned(0b11 @ idx);
  sys_spmp_enabled & (addr_idx < 64)
}

function clause read_CSR(0x1B @ idx : bits(4)) = {
  let spmp_start = getPmpNum();
  let hw_idx = spmp_start + unsigned(0b00 @ idx);
  if hw_idx < 64 then spmpaddr_n[hw_idx] else zeros()
}
function clause read_CSR(0x1C @ idx : bits(4)) = {
  let spmp_start = getPmpNum();
  let hw_idx = spmp_start + unsigned(0b01 @ idx);
  if hw_idx < 64 then spmpaddr_n[hw_idx] else zeros()
}
function clause read_CSR(0x1D @ idx : bits(4)) = {
  let spmp_start = getPmpNum();
  let hw_idx = spmp_start + unsigned(0b10 @ idx);
  if hw_idx < 64 then spmpaddr_n[hw_idx] else zeros()
}
function clause read_CSR(0x1E @ idx : bits(4)) = {
  let spmp_start = getPmpNum();
  let hw_idx = spmp_start + unsigned(0b11 @ idx);
  if hw_idx < 64 then spmpaddr_n[hw_idx] else zeros()
}

function clause write_CSR(0x1B @ idx : bits(4), value) = {
  let spmp_start = getPmpNum();
  let hw_idx = spmp_start + unsigned(0b00 @ idx);
  if hw_idx < 64 then {
    spmpWriteAddrReg(hw_idx, value);
    spmpaddr_n[hw_idx]
  } else {
    zeros()
  }
}
function clause write_CSR(0x1C @ idx : bits(4), value) = {
  let spmp_start = getPmpNum();
  let hw_idx = spmp_start + unsigned(0b01 @ idx);
  if hw_idx < 64 then {
    spmpWriteAddrReg(hw_idx, value);
    spmpaddr_n[hw_idx]
  } else {
    zeros()
  }
}
function clause write_CSR(0x1D @ idx : bits(4), value) = {
  let spmp_start = getPmpNum();
  let hw_idx = spmp_start + unsigned(0b10 @ idx);
  if hw_idx < 64 then {
    spmpWriteAddrReg(hw_idx, value);
    spmpaddr_n[hw_idx]
  } else {
    zeros()
  }
}
function clause write_CSR(0x1E @ idx : bits(4), value) = {
  let spmp_start = getPmpNum();
  let hw_idx = spmp_start + unsigned(0b11 @ idx);
  if hw_idx < 64 then {
    spmpWriteAddrReg(hw_idx, value);
    spmpaddr_n[hw_idx]
  } else {
    zeros()
  }
}
*/