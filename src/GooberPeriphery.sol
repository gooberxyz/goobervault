// SPDX-License-Identifier: MIT
// TODO(Should this be BUSL?)

pragma solidity ^0.8.17;

import "./Goober.sol";

interface IGooberPeriphery {
    function deposit(
        uint256[] calldata gobblers,
        uint256 gooTokens,
        address receiver,
        uint256 minFractionsOut,
        uint256 deadline
    ) external returns (uint256 fractions);
}

contract GooberPeriphery {
    Goober public immutable goober;

    constructor(address _gooberAddress) {
        goober = Goober(_gooberAddress);
    }

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "Goober: EXPIRED");
        _;
    }

    function deposit(
        uint256[] calldata gobblers,
        uint256 gooTokens,
        address receiver,
        uint256 minFractionsOut,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 fractionsOut) {
        fractionsOut = goober.deposit(gobblers, gooTokens, receiver);

        require(fractionsOut >= minFractionsOut, "GooberPeriphery: INSUFFICIENT_LIQUIDITY_MINTED");
    }

    function withdraw(
        uint256[] calldata gobblers,
        uint256 gooTokens,
        address receiver,
        address owner,
        uint256 maxFractionsIn,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 fractionsIn) {
        fractionsIn = goober.withdraw(gobblers, gooTokens, receiver, owner);

        require(fractionsIn <= maxFractionsIn, "GooberPeriphery: BURN_ABOVE_LIMIT");
    }

    function swap(Goober.SwapParams calldata parameters, int256 erroneousGooAbs, uint256 deadline)
        external
        ensure(deadline)
        returns (int256 erroneousGoo)
    {
        erroneousGoo = goober.swap(parameters);

        require(erroneousGoo <= erroneousGooAbs, "GooberPeriphery: EXCESSIVE_INPUT_AMOUNT");
    }
}
