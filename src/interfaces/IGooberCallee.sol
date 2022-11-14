// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import "./IGoober.sol";

interface IGooberCallee {
    function gooberCall(bytes calldata data) external;
}
