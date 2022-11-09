// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import "./IGoober.sol";

interface IGooberCallee {
    // Structs

    struct SwapParams {
        uint256[] gobblersOut;
        uint256 gooOut;
        uint256[] gobblersIn;
        uint256 gooIn;
        address owner;
        address receiver;
        bytes data;
    }

    function gooberCall(IGoober.SwapParams calldata params) external;
}
