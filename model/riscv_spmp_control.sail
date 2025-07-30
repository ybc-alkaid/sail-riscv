/*=======================================================================================*/
/*  SPMP (Supervisor Mode Physical Memory Protection) Address Range Calculation        */
/*                                                                                       */
/*  This module implements the SPMP address matching algorithms as specified in        */
/*  . SPMP operates on physical addresses after address translation    */
/*  and provides memory protection for supervisor mode software.                        */
/*=======================================================================================*/

/* SPMP address range type: None indicates no match, Some((min, max)) indicates
 * the byte-addressed range [min, max) that matches this SPMP entry.
 * Note: This follows the same semantics as PMP but operates at supervisor privilege. */
type spmp_addr_range = option((xlenbits, xlenbits))

/* Calculate the address range matched by an SPMP entry.
 * 
 * Parameters:
 *   cfg: SPMP configuration entry containing address matching type in A field
 *   spmpaddr: Current SPMP address register value (word-addressed, bits [XLEN-1:2])
 *   prev_spmpaddr: Previous SPMP address register (for TOR mode)
 * 
 * Returns: Address range [min, max) in bytes, or None if no addresses match
 * 
 * Address Matching Types:
 *   - OFF: Entry is disabled, matches no addresses
 *   - TOR: Top-of-Range, matches [prev_spmpaddr*4, spmpaddr*4)
 *   - NA4: Naturally aligned 4-byte region
 *   - NAPOT: Naturally aligned power-of-two region */
function spmpAddrRange(cfg: Spmpcfg_ent, spmpaddr: xlenbits, prev_spmpaddr: xlenbits, entry_index: nat) -> spmp_addr_range = {
  match spmpAddrMatchType_of_bits(cfg[A]) {
    /* OFF: Entry disabled - no address matching*/
    OFF   => None(),
    
    /* TOR: Top-of-Range addressing
     * Matches addresses in range [prev_spmpaddr*4, spmpaddr*4)
     * If prev_spmpaddr >= spmpaddr, no addresses match (invalid range) */
    TOR => {
      // Special case: For first SPMP entry (hw_idx == getPmpNum()) with TOR mode, use zero as lower bound
      let spmp_start = getPmpNum();
      let lower_bound = if entry_index == spmp_start then zeros() else prev_spmpaddr;
      if lower_bound >=_u spmpaddr
      then None()
      else Some((lower_bound << 2, spmpaddr << 2))
    },
    
    /* NA4: Naturally Aligned 4-byte region
     * Matches exactly 4 bytes starting at spmpaddr*4 */
    NA4   => { 
      let lo = spmpaddr << 2;  // Convert word address to byte address
      Some((lo, lo + 4))       // 4-byte region
    },
    
    /* NAPOT: Naturally Aligned Power-Of-Two region
     * Address encoding: spmpaddr = base | (size/8 - 1)
     * Where trailing 1s in spmpaddr indicate the region size */
    NAPOT => { 
      // Generate mask to identify region size (follows PMP NAPOT algorithm)
      let mask = spmpaddr ^ (spmpaddr + 1);  // XOR creates mask for trailing 1s
      let lo   = spmpaddr & (~ (mask));      // Clear low bits to get aligned base
      let len  = mask + 1;                   // Region size in words
      
      // Safety check: prevent address overflow in large regions
      if lo + len <_u lo then None()         // Overflow detected
      else Some((lo << 2, (lo + len) << 2))  // Convert to byte addresses
    }
  }
}

/*=======================================================================================*/
/*  SPMP Permission Checking Functions                                                  */
/*                                                                                       */
/*  Implements the SPMP permission matrix                                                */
/*  SPMP adds an S bit to distinguish supervisor and user accessible regions.           */
/*=======================================================================================*/

/* Basic R/W/X permission check without privilege considerations.
 * This function only checks the fundamental permission bits in the SPMP entry.
 * 
 * Parameters:
 *   ent: SPMP configuration entry with R/W/X permission bits
 *   acc: Type of memory access (Read/Write/Execute/ReadWrite)
 *   priv: Current privilege level (not used in basic check)
 * 
 * Returns: true if the basic permission bits allow the access type */
val CheckRWX: (Spmpcfg_ent, AccessType(ext_access_type), Privilege) -> bool
function CheckRWX(ent, acc, priv) = {
  match acc {
    Read(_)           => ent[R] == 0b1,  // Read permission required
    Write(_)          => ent[W] == 0b1,  // Write permission required  
    ReadWrite(_)      => ent[R] == 0b1 & ent[W] == 0b1,  // Both R&W required
    InstructionFetch() => ent[X] == 0b1  // Execute permission required
  }
}

/* SPMP privilege-aware permission check implementing the complete permission matrix.
 * 
 * Based on the detailed permission matrix specification, SPMP has three kinds of rules:
 *   1. S-mode-only rules (SHARED=0, U=0): Enforced on S-mode, denied on U-mode
 *   2. U-mode-only rules (SHARED=0, U=1): Enforced on U-mode, conditional on S-mode  
 *   3. Shared-Region rules (SHARED=1): Enforced on both modes (U bit ignored)
 * 
 * Permission Matrix Implementation:
 *   - XWR=000: Always Deny (no permissions)
 *   - XWR=001: Read-only (R=1, W=0, X=0)
 *   - XWR=010: Reserved (or shadow stack if Zicfiss enabled)
 *   - XWR=011: Read-only (R=1, W=0, X=0) 
 *   - XWR=100: Execute-only (R=0, W=0, X=1)
 *   - XWR=101: Read+Execute (R=1, W=0, X=1)
 *   - XWR=110: Reserved
 *   - XWR=111: Read+Write+Execute (R=1, W=1, X=1) - Special handling in Shared-Region U-mode
 */
val spmpCheckRWX: (Spmpcfg_ent, AccessType(ext_access_type), Privilege) -> bool
function spmpCheckRWX(ent, acc, priv) = {
  let do_sum : bool = mstatus[SUM] == 0b1;  // Check SUM bit in mstatus (accessible via sstatus)
  let xwr = ent[X] @ ent[W] @ ent[R];       // Extract XWR field for encoding checks
  
  /* Always deny XWR=000 regardless of configuration */
  if xwr == 0b000 then {
    false
  }
  /* Check for reserved encodings: XWR=010 and XWR=110 */
  else if (xwr == 0b010) | (xwr == 0b110) then {
    /* XWR=010: Shadow stack region if Zicfiss enabled, else reserved */
    /* For now, treat as reserved (deny access) */
    /* TODO: Implement Zicfiss shadow stack support */
    false
  }
  /* Check for Shared-Region rules (SHARED=1) - U bit and SUM bit are ignored */
  else if ent[SHARED] == 0b1 then {
    match priv {
      Supervisor => {
        /* S-mode in Shared-Region: Always "Enforce" - standard R/W/X permissions */
        match acc {
          Read(_)            => ent[R] == 0b1,
          Write(_)           => ent[W] == 0b1,
          ReadWrite(_)       => ent[R] == 0b1 & ent[W] == 0b1,
          InstructionFetch() => ent[X] == 0b1,
        }
      },
      User => {
        /* U-mode in Shared-Region: Special handling */
        match xwr {
          0b001 => {  /* XWR=001: Enforce (standard R/W/X) */
            match acc {
              Read(_)            => ent[R] == 0b1,
              Write(_)           => ent[W] == 0b1,
              ReadWrite(_)       => ent[R] == 0b1 & ent[W] == 0b1,
              InstructionFetch() => ent[X] == 0b1,
            }
          },
          0b011 => {  /* XWR=011: Read-only in U-mode for Shared-Region */
            match acc {
              Read(_)            => ent[R] == 0b1,    // Allow read if R bit set
              Write(_)           => false,            // Deny write (Read-only)
              ReadWrite(_)       => false,            // Deny read-write (Read-only)
              InstructionFetch() => false,            // Deny execute (Read-only)
            }
          },
          0b100 => {  /* XWR=100: Enforce (standard R/W/X) */
            match acc {
              Read(_)            => ent[R] == 0b1,
              Write(_)           => ent[W] == 0b1,
              ReadWrite(_)       => ent[R] == 0b1 & ent[W] == 0b1,
              InstructionFetch() => ent[X] == 0b1,
            }
          },
          0b101 => {  /* XWR=101: Enforce (standard R/W/X) */
            match acc {
              Read(_)            => ent[R] == 0b1,
              Write(_)           => ent[W] == 0b1,
              ReadWrite(_)       => ent[R] == 0b1 & ent[W] == 0b1,
              InstructionFetch() => ent[X] == 0b1,
            }
          },
          0b111 => {  /* XWR=111: Exec-only in U-mode for Shared-Region */
            match acc {
              Read(_)            => false,    // No read in Exec-only
              Write(_)           => false,    // No write in Exec-only
              ReadWrite(_)       => false,    // No read/write in Exec-only
              InstructionFetch() => ent[X] == 0b1,  // Only execute allowed
            }
          },
          _ => {  /* Other XWR values: standard enforcement */
            match acc {
              Read(_)            => ent[R] == 0b1,
              Write(_)           => ent[W] == 0b1,
              ReadWrite(_)       => ent[R] == 0b1 & ent[W] == 0b1,
              InstructionFetch() => ent[X] == 0b1,
            }
          }
        }
      },
      Machine => true  // Machine mode bypasses
    }
  }
  /* S-mode-only rule (SHARED=0, U=0) */
  else if ent[U] == 0b0 then {
    match priv {
      Supervisor => {
        /* S-mode: Always Enforce - standard R/W/X permissions apply */
        match acc {
          Read(_)            => ent[R] == 0b1,
          Write(_)           => ent[W] == 0b1,
          ReadWrite(_)       => ent[R] == 0b1 & ent[W] == 0b1,
          InstructionFetch() => ent[X] == 0b1,
        }
      },
      User => {
        /* U-mode: Always Deny for S-mode-only rules */
        false
      },
      Machine => true  // Machine mode bypasses
    }
  }
  /* U-mode-only rule (SHARED=0, U=1) */
  else {
    match priv {
      Supervisor => {
        /* S-mode: Access depends on SUM bit for SMAP/SMEP */
        if do_sum then {
          /* SUM=1: EnforceNoX - R/W allowed but execute denied (SMEP) */
          match acc {
            Read(_)            => ent[R] == 0b1,
            Write(_)           => ent[W] == 0b1,
            ReadWrite(_)       => ent[R] == 0b1 & ent[W] == 0b1,
            InstructionFetch() => false  // SMEP: S-mode cannot execute from U-mode pages
          }
        } else {
          /* SUM=0: Deny - S-mode cannot access U-mode-only pages (SMAP) */
          false
        }
      },
      User => {
        /* U-mode: Always Enforce - standard R/W/X permissions apply */
        match acc {
          Read(_)            => ent[R] == 0b1,
          Write(_)           => ent[W] == 0b1,
          ReadWrite(_)       => ent[R] == 0b1 & ent[W] == 0b1,
          InstructionFetch() => ent[X] == 0b1,
        }
      },
      Machine => true  // Machine mode bypasses
    }
  }
}

/* High-level SPMP permission check entry point.
 * 
 * Machine mode behavior :
 *   - Machine mode bypasses all SPMP checks
 *   - This follows the principle that machine mode has unrestricted access
 *   - Only supervisor and user modes are subject to SPMP restrictions
 * 
 * Parameters:
 *   ent: SPMP configuration entry to check against
 *   acc: Memory access type being attempted
 *   priv: Current effective privilege level
 * 
 * Returns: true if access should be permitted, false if denied */
val spmpCheckPerms: (Spmpcfg_ent, AccessType(ext_access_type), Privilege) -> bool
function spmpCheckPerms(ent, acc, priv) = {
  match priv {
    /* Machine mode: Always bypass SPMP checks */
    Machine => true,
    /* Supervisor/User mode: Apply full SPMP permission matrix */
    _       => spmpCheckRWX(ent, acc, priv)
  }
}

/*=======================================================================================*/
/*  SPMP Address Matching Logic                                                         */
/*                                                                                       */
/*  Implements address range matching for SPMP entries. Unlike PMP, partial matches    */
/*  are treated as violations per .                                                   */
/*=======================================================================================*/

/* SPMP address matching result types */
enum spmpAddrMatch = {SPMP_NoMatch, SPMP_PartialMatch, SPMP_Match}

/* Determine relationship between access range and SPMP protection range.
 * 
 * SPMP requires that memory accesses either:
 *   1. Completely fall within a protected region (SPMP_Match)
 *   2. Completely fall outside all protected regions (SPMP_NoMatch)
 *   3. Partially overlap a region (SPMP_PartialMatch - this is a violation)
 * 
 * If any byte of an access partially matches
 * an SPMP entry, the entire access fails.
 * 
 * Parameters:
 *   begin: Start of SPMP protected region (inclusive)
 *   end_: End of SPMP protected region (exclusive) 
 *   addr: Start address of memory access
 *   width: Size of memory access in bytes
 * 
 * Returns: Relationship between access [addr, addr+width) and region [begin, end_) */
function spmpRangeMatch(
  begin : nat,
  end_ : nat,
  addr : nat,
  width : nat,
) -> spmpAddrMatch =
  if      (addr + width <= begin) | (end_ <= addr)
  then    SPMP_NoMatch      // Access completely outside region
  else if (begin <= addr) & (addr + width <= end_)
  then    SPMP_Match        // Access completely within region
  else    SPMP_PartialMatch // Access partially overlaps region (violation)

/* Match a memory access against an SPMP address range.
 * 
 * Parameters:
 *   addr: Physical address of access
 *   width: Width of access in bytes
 *   rng: SPMP address range (None if entry disabled)
 * 
 * Returns: Address match result */
function spmpMatchAddr(addr: nat, width: nat, rng: spmp_addr_range) -> spmpAddrMatch = {
  match rng {
    None()         => SPMP_NoMatch,  // Entry disabled
    Some((lo, hi)) => if   hi <_u lo   /* Handle misconfigured ranges */
                      then SPMP_NoMatch
                      else {
                        let lo_nat = unsigned(lo);
                        let hi_nat = unsigned(hi);
                        spmpRangeMatch(lo_nat, hi_nat, addr, width)
                      }
  }
}

/*=======================================================================================*/
/*  SPMP Entry Matching and Result Types                                                */
/*=======================================================================================*/

/* SPMP matching results for individual entries */
enum spmpMatch = {SPMP_Success, SPMP_Continue, SPMP_Fail}

/* Match a memory access against a single SPMP entry.
 * 
 * NOTE: This function is kept for compatibility but is no longer used 
 * by the main spmpCheck function, which implements the revised matching logic directly.
 * 
 * This function implements the complete SPMP checking algorithm for one entry:
 *   1. Check if the access address range matches the entry's protected range
 *   2. If matched, verify permissions according to privilege level and S bit
 *   3. Return appropriate result for SPMP decision
 * 
 * SPMP entries are checked in order from 0 to 63.
 * The first matching entry determines the access result.
 * 
 * Parameters:
 *   Physaddr(addr): Physical address being accessed
 *   width: Access width in bytes 
 *   acc: Type of memory access (read/write/execute)
 *   priv: Current privilege level
 *   ent: SPMP configuration entry being checked
 *   spmpaddr: Address register value for this entry
 *   prev_spmpaddr: Previous entry's address (needed for TOR mode)
 * 
 * Returns:
 *   SPMP_Success: Access granted by this entry
 *   SPMP_Fail: Access denied by this entry  
 *   SPMP_Continue: This entry doesn't match, check next entry */
function spmpMatchEntry(Physaddr(addr): physaddr, width: xlenbits, acc: AccessType(ext_access_type), priv: Privilege,
                       ent: Spmpcfg_ent, spmpaddr: xlenbits, prev_spmpaddr: xlenbits, entry_index: nat) -> spmpMatch = {
  let addr = unsigned(addr);
  let width = unsigned(width);
  let rng = spmpAddrRange(ent, spmpaddr, prev_spmpaddr, entry_index);
  match spmpMatchAddr(addr, width, rng) {
    SPMP_NoMatch      => SPMP_Continue,     // No match, try next entry
    SPMP_PartialMatch => SPMP_Fail,         // Partial match is violation
    SPMP_Match        => if   spmpCheckPerms(ent, acc, priv)
                        then SPMP_Success   // Full match with permission
                        else SPMP_Fail      // Full match without permission
  }
}

/*=======================================================================================*/
/*  SPMP Exception Handling                                                             */
/*                                                                                       */
/*  SPMP violations generate Page Fault exceptions, distinguishing them from PMP        */
/*=======================================================================================*/

/* Convert memory access type to appropriate SPMP Page Fault exception.
 * 
 * Key difference from PMP :
 *   - PMP violations → Access Fault exceptions
 *   - SPMP violations → Page Fault exceptions  
 * 
 * This distinction allows OS kernels to differentiate between:
 *   - Page-level protection violations (SPMP) 
 *   - Platform-level protection violations (PMP)
 * 
 * Exception types follow standard RISC-V privilege specification. */
function accessToSpmpFault(acc : AccessType(ext_access_type)) -> ExceptionType =
  match acc {
    Read(_)            => E_Load_Page_Fault(),     // Load page fault
    Write(_)           => E_SAMO_Page_Fault(),     // Store/AMO page fault  
    ReadWrite(_)       => E_SAMO_Page_Fault(),     // Store/AMO page fault
    InstructionFetch() => E_Fetch_Page_Fault()     // Instruction page fault
  }

/*=======================================================================================*/
/*  SPMP Register Access Functions                                                      */
/*                                                                                       */
/*  Provides unified access to all 64 SPMP entries. SPMP supports the same number       */
/*  of entries as PMP for consistency.                                                  */
/*=======================================================================================*/

/* Retrieve SPMP configuration and address register pair for hardware entry i.
 * 
 * SPMP supports 64 entries (0-63) same as PMP, each with:
 *   - One configuration entry (8 bits in spmpcfg registers)
 *   - One address register (spmpaddr registers)
 * 
 * This function provides unified access across all entries for the
 * main SPMP checking loop. The parameter i is a hardware index (pmpnum to 63). */
function spmpGetEntry(i: nat) -> (Spmpcfg_ent, xlenbits) = {
  if i < 64 then (spmp_read_cfg_indirect(i), spmp_read_addr_indirect(i))
  else (Mk_Spmpcfg_ent(0x0000), zeros())  // fallback case
}

/* SPMP Context Switch Optimization Helper Functions */

/* Check if an SPMP entry is active based on spmpswitch and configuration.
 * 
 * Activation Rule:
 * - An entry is active only when: spmpswitch[i] & (spmp[i]cfg.A != OFF)
 * 
 * Special Cases:
 * - When spmpswitch[i] == 0 and spmp[i]cfg.L == 1, entry i remains enabled
 * - TOR entries match regardless of spmpswitch[i-1] value
 */
function spmpEntryActive(hw_idx: range(0, 63), cfg: Spmpcfg_ent) -> bool = {
  let match_type = spmpAddrMatchType_of_bits(cfg[A]);
  let switch_bit = if xlen == 32 then {
    if hw_idx < 32 then spmpswitch[hw_idx] else spmpswitchh[hw_idx - 32]
  } else {
    spmpswitch[hw_idx]
  };

  // Special case: locked entries remain enabled even when switch bit is 0
  let is_locked = spmpLocked(cfg);
  if is_locked then true
  else {
    /* Entry is active if:
        * 1. Switch bit is set, OR
        * 2. Entry is locked (locked entries always remain enabled), OR 
        * 3. Entry is TOR mode (TOR entries always match when A != OFF) */
    (switch_bit == bitone) & (match_type != OFF)
  }
}

// defined in riscv_vmem.sail 
val translationMode: Privilege -> SATPMode

/*=======================================================================================*/
/*  Main SPMP Checking Function                                                         */
/*                                                                                       */
/*  Primary entry point for SPMP access control checks. Implements the complete        */
/*  SPMP algorithm                                                                       */
/*=======================================================================================*/

/* Perform SPMP access control check for a memory operation.
 * 
 * SPMP and Paging Interaction:
 *   - SPMP is enabled when satp.mode == Bare and SPMP is implemented
 *   - SPMP and paged virtual memory are mutually exclusive
 *   - When satp.mode != Bare, paged virtual memory provides protection instead
 *   - Machine mode always uses SPMP if implemented (M-mode doesn't use virtual memory)
 * 
 * Matching Logic:
 *   1. SPMP entries are statically prioritized (0-63 in order)
 *   2. The lowest-numbered SPMP entry that matches any byte of access determines the result
 *   3. The SPMP entry must match ALL bytes of access, or the access fails
 *   4. Address matching is done irrespective of the S, R, W, and X bits
 * 
 * Access Control Rules:
 *   1. Calculate effective privilege mode considering MPRV bit
 *   2. If effective privilege mode is M, the access is allowed
 *   3. If effective privilege mode is S/U and no SPMP entry matches, but at least 
 *      one SPMP entry is delegated, the access is denied
 *   4. Otherwise, access is checked according to permission bits in matching SPMP entry
 * 
 * Parameters:
 *   addr: Physical address of the memory access
 *   width: Size of the access in bytes (1, 2, 4, 8, etc.)
 *   acc: Type of access (Read/Write/Execute/ReadWrite)
 *   priv: Current privilege level of the accessing code
 * 
 * Returns:
 *   None(): Access allowed
 *   Some(exception): Access denied with specific page fault type */
function spmpCheck forall 'n, 0 < 'n <= max_mem_access . (
  addr: physaddr,
  width: int('n),
  acc: AccessType(ext_access_type),
  priv: Privilege
) -> option(ExceptionType) = {
  let width : xlenbits = to_bits(width);
  
  /* SPMP Enablement Check: SPMP is only active when satp.mode == Bare
   * When paged virtual memory is active (satp.mode != Bare), SPMP is disabled
   * and this function should allow all accesses to proceed */
  if not(sys_spmp_enabled) then return None();  // SPMP not implemented
  
  /* Check SPMP and Paging interaction:
   * - Machine mode: Always uses SPMP if implemented (Machine mode doesn't use virtual memory)
   * - Supervisor/User modes: SPMP is only active when satp.mode == Bare
   * - When satp.mode != Bare, paged virtual memory provides protection instead
   * 
   * This ensures SPMP and paged virtual memory are mutually exclusive per spec.
   */
  if priv != Machine then {
    // For S/U modes: SPMP is only active when translation mode is Bare
    // When paged virtual memory is active, SPMP is disabled and access is allowed
    if translationMode(priv) != Bare then {
      return None()  // Paged virtual memory active, SPMP disabled
    }
  };
  
  /* Rule 1: Calculate effective privilege mode for SPMP checking
   * 
   * SPMP checks will be applied to all accesses whose effective privilege mode is S or U:
   * - Instruction fetches and data accesses in S and U mode
   * - Data accesses in M-mode when MPRV=1 and MPP contains S or U
   * 
   * The effective privilege mode is determined by:
   * - Normal case: Current privilege level
   * - MPRV case: When cur_privilege=M and mstatus.MPRV=1, use mstatus.MPP for data accesses
   */
  let effective_priv : Privilege = match (priv, acc) {
    (Machine, InstructionFetch(_)) => Machine,  // M-mode instruction fetches always use M-mode
    (Machine, _) => {
      // M-mode data access: Check MPRV bit
      if mstatus[MPRV] == 0b1 then {
        // MPRV=1: Use MPP as effective privilege for data accesses
        privLevel_of_bits(mstatus[MPP])
      } else {
        // MPRV=0: Use current privilege
        Machine
      }
    },
    (_, _) => priv  // S/U mode: Always use current privilege
  };
  
  /* Rule 2: If effective privilege mode is M, the access is allowed */
  match effective_priv {
    Machine => return None(),  // M-mode bypasses all SPMP checks
    _ => ()
  };
  
  /* Check all SPMP entries in order for address matching.
   * SPMP entries begin from hardware index pmpnum and go to 63 */
  var has_delegated_entries : bool = false;  // Track if any SPMP entries are delegated
  let spmp_start = getPmpNum();  // First hardware resource allocated to SPMP
  let spmp_end = 63;             // Last hardware resource (always 63)
  
  var prev_spmpaddr : xlenbits = zeros();  // Previous address for TOR mode
  
  foreach (hw_idx from spmp_start to spmp_end) {
    /* Get current entry configuration and address using hardware index */
    let (cfg, spmpaddr) = spmpGetEntry(hw_idx);
    
    /* For TOR mode: first SPMP entry (hw_idx == spmp_start) uses 0 as lower bound, 
     * others use previous entry */
    let current_prev_addr = if hw_idx == spmp_start then zeros() else prev_spmpaddr;
    
    /* Check if this entry is delegated (enabled/configured) */
    let is_delegated = spmpAddrMatchType_of_bits(cfg[A]) != OFF;
    has_delegated_entries = has_delegated_entries | is_delegated;
    
    /* Check if entry is active - use spmpEntryActive function with hardware index and config */
    let is_active = if is_delegated then {
      spmpEntryActive(hw_idx, cfg)  // Use helper function with hardware index and config
    } else false;
    
    /* Only check active entries for address matching */
    if is_active then {
      /* Check address matching (irrespective of S, R, W, X bits) */
      let Physaddr(addr_bits) = addr;
      let addr_nat = unsigned(addr_bits);
      let width_nat = unsigned(width);
      let rng = spmpAddrRange(cfg, spmpaddr, current_prev_addr, hw_idx);
      
      match spmpMatchAddr(addr_nat, width_nat, rng) {
        SPMP_NoMatch      => (),  // Continue to next entry
        SPMP_PartialMatch => return Some(accessToSpmpFault(acc)),  // Partial match fails
        SPMP_Match        => {
          /* Full address match found - check permissions using effective privilege mode */
          return if spmpCheckPerms(cfg, acc, effective_priv)
                 then None()                        // Access granted
                 else Some(accessToSpmpFault(acc))  // Access denied
        }
      }
    };
    
    /* Update previous address for next iteration */
    prev_spmpaddr = spmpaddr;
  };

  /* Rule 3: No SPMP entry matched, check delegation status */
  if has_delegated_entries then {
    /* At least one SPMP entry is delegated but none matched - deny access */
    Some(accessToSpmpFault(acc))
  } else {
    /* No SPMP entries are delegated - allow access (backward compatibility) */
    None()
  }
}

/*=======================================================================================*/
/*  SPMP Reset and Initialization                                                       */
/*=======================================================================================*/

/* Initialize SPMP to safe default state.
 * 
 * SPMP should be initialized to allow all
 * access by default to maintain compatibility with existing software.
 * 
 * Reset behavior:
 *   - All entries set to OFF (disabled) state
 *   - No memory regions protected initially  
 *   - All accesses allowed until SPMP entries are configured
 *   - L bits are cleared (only possible during reset by hardware/M-mode)
 * 
 * This differs from PMP reset which typically denies access by default. 
 * 
 * NOTE: This function should only be called during system reset or by M-mode code.
 * The L bit can only be cleared by M-mode or hardware reset. */
function reset_spmp() -> unit = {
  /* Reset only hardware resources allocated to SPMP (from getPmpNum() to 63) */
  let spmp_start = getPmpNum();
  foreach (hw_idx from spmp_start to 63) {
    // On reset the SPMP register's A field is set to OFF (disabled) and L bit is cleared.
    // This is the only way to clear L bits after they have been set.
    let reset_cfg = Mk_Spmpcfg_ent(0x0000);  // All bits cleared
    spmp_mmode_write_cfg_indirect(hw_idx, reset_cfg);
    spmp_write_addr_indirect(hw_idx, zeros());
  };

  /* Reset SPMP switch registers - must be cleared on reset */
  spmpSwitchReset();

  /* After reset, SPMP allows all access by default.
   * This ensures backwards compatibility with software that is unaware of SPMP.
   * Explicit configuration is required to enable protection. */
}



/* Helper function to unlock SPMP entry (M-mode only).
 * This function can be used by M-mode software to unlock specific SPMP entries.
 * Note: This should only be called from M-mode context.
 */
function spmpUnlock(n: range(0, 63)) -> unit = {
  // Only M-mode can unlock entries
  if cur_privilege == Machine then {
    let cfg = spmp_read_cfg_indirect(n);
    let unlocked_cfg = [cfg with L = 0b0];
    spmp_mmode_write_cfg_indirect(n, unlocked_cfg);
  }
}

/*=======================================================================================*/
/*  SPMP Configuration Validation                                                       */
/*                                                                                       */
/*  Validation functions to ensure SPMP entries are configured correctly.               */
/*=======================================================================================*/

/* Validate SPMP configuration entry for correctness.
 * 
 * Checks entry-specific constraints based on address matching mode.
 * Invalid configurations may lead to unpredictable behavior.
 * 
 * Parameters:
 *   i: Entry index (0-63)
 *   cfg: Configuration entry to validate
 *   spmpaddr: Address register value
 * 
 * Returns: true if configuration is valid */
function spmpValidateConfig(i: nat, cfg: Spmpcfg_ent, spmpaddr: xlenbits) -> bool = {
  match spmpAddrMatchType_of_bits(cfg[A]) {
    /* OFF: Always valid - entry is disabled */
    OFF => true,
    
    /* TOR: Validate address ordering for proper range */
    TOR => {
      if i == 0 then spmpaddr != zeros()  // First entry needs non-zero address
      else {
        let (_, prev_addr) = spmpGetEntry(i - 1);
        prev_addr <_u spmpaddr  // Ensure prev_addr < spmpaddr for valid range
      }
    },
    
    /* NA4: Validate 4-byte alignment */
    NA4 => {
      spmpaddr[1..0] == zeros()  // Bottom 2 bits must be 0 for word alignment
    },
    
    /* NAPOT: Validate power-of-2 region encoding */
    NAPOT => {
      let mask = spmpaddr ^ (spmpaddr + 1);
      let trailing_ones = spmpaddr & mask;
      trailing_ones == mask  // Validate that trailing bits form proper NAPOT encoding
    }
  }
}

/* Note: Enhanced debugging support omitted to avoid compilation issues.
 * Debug functions can be added later with proper string handling. */
