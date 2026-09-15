// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @dev A contract that has code but no `owner()` function and no fallback, so a staticcall to
/// `owner()` reverts. Used to prove CowSwapModuleFactory rejects targets whose ownership cannot
/// be resolved instead of deploying a module bound to them.
contract MockOwnerlessTarget {
    uint256 public immutable filler = 1;
}

/// @dev A contract whose fallback answers every call — including `owner()` — with return data that
/// is too short to decode as an address. Proves the factory treats an undecodable answer as a
/// lookup failure rather than reverting on ABI decoding or reading a garbage owner.
contract MockMalformedOwnerTarget {
    fallback() external {
        assembly {
            mstore(0x00, 0x01)
            return(0x00, 0x08)
        }
    }
}

/// @dev A contract whose fallback answers `owner()` with a full 32-byte word that is not canonical
/// ABI padding — the upper 96 bits are set. Proves the factory reports this as a lookup failure
/// instead of reverting inside `abi.decode` with empty revert data.
contract MockDirtyOwnerTarget {
    fallback() external {
        assembly {
            mstore(0x00, not(0))
            return(0x00, 0x20)
        }
    }
}
