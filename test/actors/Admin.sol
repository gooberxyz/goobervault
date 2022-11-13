// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./InvariantActor.sol";

/// @dev The Admin randomly mints Gobblers and skims.
contract Admin is InvariantActor {
    address internal constant FEE_TO = address(0xFEEE);
    address internal constant MINTER = address(0x1337);

    constructor(
        Goober _goober,
        Goo _goo,
        ArtGobblers _gobblers,
        RandProvider _randProvider,
        VRFCoordinatorMock _vrfCoordinator
    ) InvariantActor(_goober, _goo, _gobblers, _randProvider, _vrfCoordinator) {}

    function mint() external {
        vm.prank(MINTER);
        goober.mintGobbler();
    }

    function skim() external {
        vm.prank(FEE_TO);
        goober.skimGoo();
    }
}
