// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./InvariantActor.sol";

/// @dev The Admin randomly mints Gobblers and skims.
contract Admin is InvariantActor {
    address internal constant FEE_TO = address(0xFEEE);

    constructor(
        Goober _goober,
        Goo _goo,
        ArtGobblers _gobblers,
        RandProvider _randProvider,
        VRFCoordinatorMock _vrfCoordinator
    ) InvariantActor(_goober, _goo, _gobblers, _randProvider, _vrfCoordinator) {}

    function skim() external {
        vm.prank(FEE_TO);
        uint256 gooTankBalance = gobblers.gooBalance(address(goober));
        if (gooTankBalance >= type(uint112).max) {
            goober.skimGoo();
        }
    }
}

/// @dev The Minter randomly mints Gobblers.
contract Minter is InvariantActor {
    using FixedPointMathLib for uint256;

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
        uint256 gooReserve = gobblers.gooBalance(address(this));
        uint256 gobblerReserve = gobblers.getUserEmissionMultiple(address(this));
        uint256 mintPrice = gobblers.gobblerPrice();
        uint256 gooPerMult = (gooReserve / gobblerReserve);
        // TODO(Account for slippage)
        bool mint = gooPerMult > (mintPrice * 1e4) / 73294;
        if (mint) {
            goober.mintGobbler();
        }
    }
}
