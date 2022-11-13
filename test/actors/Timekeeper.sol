// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {CommonBase} from "forge-std/Common.sol";

/// @dev The Father time warps forward a random number of days and blocks
contract Timekeeper is CommonBase {
    function tick(uint8 numDays, uint16 numBlocks) external {
        vm.warp(block.timestamp + uint256(numDays) * 1 days);
        vm.roll(block.number + numBlocks);
    }
}
