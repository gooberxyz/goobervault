// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IGooberCallee {
    function gooberCall(bytes calldata data) external;
}
