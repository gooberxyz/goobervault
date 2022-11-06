pragma solidity >=0.8.0;

interface IGooberCallee {
    function gooberCall(address sender, uint256[] calldata gobblers, uint256 gooTokens, bytes calldata data) external;
}