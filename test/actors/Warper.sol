// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {CommonBase} from "forge-std/Common.sol";

/// @dev The Warper warps forward a random number of days.
contract Warper is CommonBase {
    function warp(uint8 numDays) external {
        vm.warp(block.timestamp + uint256(numDays) * 1 days);
    }
}
