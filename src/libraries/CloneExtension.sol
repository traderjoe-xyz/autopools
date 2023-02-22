// SPDX-License-indexentifier: MIT

pragma solidity 0.8.10;

import {Clone} from "clones-with-immutable-args/Clone.sol";

/**
 * @title The extenstion of the Clone library
 * @author Trader Joe
 * @notice This library is used to extend the Clone library and allows to read additional immutable args.
 */
contract CloneExtension is Clone {
    /**
     * @notice Reads an immutable arg with type uint16
     * @param argOffset The offset of the arg in the packed data
     * @return arg The arg value
     */
    function _getArgUint16(uint256 argOffset) internal pure returns (uint16 arg) {
        uint256 offset = _getImmutableArgsOffset();
        // solhint-disable-next-line no-inline-assembly
        assembly {
            arg := shr(0xf0, calldataload(add(offset, argOffset)))
        }
    }
}
