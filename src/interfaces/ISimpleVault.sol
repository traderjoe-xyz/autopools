// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {IERC20Upgradeable} from "openzeppelin-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {ILBPair} from "joe-v2/interfaces/ILBPair.sol";

import {IStrategy} from "./IStrategy.sol";
import {IBaseVault} from "./IBaseVault.sol";

interface ISimpleVault is IBaseVault {
    error SimpleVault__AmountsOverflow();
    error SimpleVault__ZeroCross();
}
