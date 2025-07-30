/*=======================================================================================*/
/*  SPMP (Supervisor Mode Physical Memory Protection) Utility Functions                */
/*                                                                                       */
/*  This module provides helper functions for SPMP testing, debugging, and             */
/*  configuration management. These utilities support the main SPMP implementation     */
/*  without being part of the core protection logic.                                    */
/*=======================================================================================*/

/*=======================================================================================*/
/*  Access Type Classification Functions                                                */
/*                                                                                       */
/*  These functions provide convenient type checking for memory access patterns        */
/*  used in SPMP permission validation and testing.                                     */
/*=======================================================================================*/

/* Check if access is a read operation (load instructions) */
function spmp_isRead(acc: AccessType(ext_access_type)) -> bool = {
  match acc {
    Read(_) => true,   // Pure read access
    _ => false
  }
}

/* Check if access is a write operation (store instructions) */
function spmp_isWrite(acc: AccessType(ext_access_type)) -> bool = {
  match acc {
    Write(_) => true,  // Pure write access
    _ => false
  }
}

/* Check if access is a read-write operation (atomic instructions) */
function spmp_isReadWrite(acc: AccessType(ext_access_type)) -> bool = {
  match acc {
    ReadWrite(_) => true,  // Atomic read-modify-write operation
    _ => false
  }
}

/* Check if access is instruction fetch (execution) */
function spmp_isInstructionFetch(acc: AccessType(ext_access_type)) -> bool = {
  match acc {
    InstructionFetch() => true,  // Instruction fetch for execution
    _ => false
  }
}

/*=======================================================================================*/
/*  SPMP Configuration Access Functions                                                 */
/*                                                                                       */
/*  These functions provide direct access to SPMP configuration entries by index.      */
/*  Used for testing, debugging, and configuration validation.                          */
/*=======================================================================================*/

/* Retrieve SPMP configuration entry by index (0-63).
 * 
 * This function provides read-only access to SPMP configuration entries
 * for testing and validation purposes. Each configuration entry contains
 * the R/W/X/S/A permission and addressing mode bits.
 * 
 * Parameters:
 *   i: SPMP entry index (0-63)
 * 
 * Returns: Configuration entry for the specified index */
function spmpGetCfg(i: nat) -> Spmpcfg_ent = {
  if i < 64 then spmp_read_cfg_indirect(i) else Mk_Spmpcfg_ent(0x00)  // fallback case
}

/* Helper function to get SPMP address entry by index */
function spmpGetAddr(i: nat) -> xlenbits = {
  if i < 64 then spmp_read_addr_indirect(i) else zeros()  // fallback case
}

/* Helper function to set SPMP configuration entry */
function spmpSetCfg(i: nat, cfg: Spmpcfg_ent) -> unit = {
  if i < 64 then spmp_write_cfg_indirect(i, cfg) else ()  // fallback case - do nothing
}

/* Helper function to set SPMP address entry */  
function spmpSetAddr(i: nat, addr: xlenbits) -> unit = {
  if i < 64 then spmp_write_addr_indirect(i, addr) else ()  // fallback case - do nothing
}
