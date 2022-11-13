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

    // TODO(Skimming goo breaks invariants)
    function skim() external {
        //vm.startPrank(FEE_TO);
        //uint256 gooTankBalance = gobblers.gooBalance(address(goober));
        //if (gooTankBalance >= type(uint112).max) {
        //    goober.skimGoo();
        //}
        //vm.stopPrank();
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
        vm.startPrank(MINTER);
        uint256 gooBalance = gobblers.gooBalance(address(this));
        uint256 gobblerBalance = gobblers.getUserEmissionMultiple(address(this));
        uint256 auctionPrice = gobblers.gobblerPrice();
        uint256 auctionPricePerMult = 0;
        uint256 poolPricePerMult = 0;
        if (gooBalance == 0 || gobblerBalance == 0) {
            vm.expectRevert(abi.encodeWithSelector(IGoober.InsufficientLiquidity.selector, gooBalance, gobblerBalance));
            goober.mintGobbler();
        } else {
            if (gobblerBalance > 0) {
                if (gooBalance > auctionPrice) {
                // No loss of precision as bps scalars cancel out.
                auctionPricePerMult = (auctionPrice * 10000) / 73294;
                poolPricePerMult = (gooBalance / gobblerBalance);
                goober.mintGobbler();
            }
        }
        vm.stopPrank();
    }
}
