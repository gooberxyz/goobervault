// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import "art-gobblers/Goo.sol";
import "art-gobblers/../lib/chainlink/contracts/src/v0.8/mocks/VRFCoordinatorMock.sol";
import {ChainlinkV1RandProvider} from "art-gobblers/utils/rand/ChainlinkV1RandProvider.sol";
import "../../src/Goober.sol";

abstract contract InvariantActor is StdUtils, CommonBase {
    using stdStorage for StdStorage;

    Goober internal goober;
    Goo internal goo;
    ArtGobblers internal gobblers;
    RandProvider internal randProvider;
    VRFCoordinatorMock internal vrfCoordinator;

    uint256[] internal gobblerPool;

    constructor(
        Goober _goober,
        Goo _goo,
        ArtGobblers _gobblers,
        RandProvider _randProvider,
        VRFCoordinatorMock _vrfCoordinator
    ) {
        goober = _goober;
        goo = _goo;
        gobblers = _gobblers;
        randProvider = _randProvider;
        vrfCoordinator = _vrfCoordinator;

        // Approve all goo to Goober
        goo.approve(address(goober), type(uint256).max);

        // Approve all gobblers to Goober
        gobblers.setApprovalForAll(address(goober), true);

        // Mint a pool of 300 Gobblers. Actors can draw from
        // this pool when they need Gobblers to swap/deposit.
        gobblerPool = _mintGobblers(address(this), 300);

        // Warp forward a full year, since the VRGDA price
        // of Gobblers is now very high.
        vm.warp(block.timestamp + 365 days);
    }

    function _drawGobblers(uint256 numGobblers) internal returns (uint256[] memory) {
        uint256[] memory gobblerIds = new uint256[](numGobblers);
        for (uint256 i; i < numGobblers; i++) {
            gobblerIds[i] = gobblerPool[gobblerPool.length - 1];
            gobblerPool.pop();
        }
        return gobblerIds;
    }

    function _returnGobblers(uint256[] memory gobblerIds) internal {
        for (uint256 i; i < gobblerIds.length; i++) {
            gobblerPool.push(gobblerIds[i]);
        }
    }

    function _mintGobblers(address who, uint256 numGobblers) private returns (uint256[] memory) {
        uint256[] memory mintedGobblers = new uint256[](numGobblers);
        if (numGobblers == 0) return mintedGobblers;
        for (uint256 i = 0; i < numGobblers; i++) {
            uint256 price = gobblers.gobblerPrice();
            _writeTokenBalance(address(this), address(goo), price);
            gobblers.addGoo(price);
            uint256 id = gobblers.mintFromGoo(price, true);
            gobblers.transferFrom(address(this), who, id);
            mintedGobblers[i] = id;
        }
        vm.warp(block.timestamp + 1 days);
        _setRandomnessAndReveal(numGobblers, "seed");
        return mintedGobblers;
    }

    function _writeTokenBalance(address who, address token, uint256 amt) internal {
        stdstore.target(token).sig(IERC20(token).balanceOf.selector).with_key(who).checked_write(amt);
    }

    /// @dev Call back vrf with randomness and reveal gobblers.
    function _setRandomnessAndReveal(uint256 numReveal, string memory seed) private {
        bytes32 requestId = gobblers.requestRandomSeed();
        uint256 randomness = uint256(keccak256(abi.encodePacked(seed)));
        // call back from coordinator
        vrfCoordinator.callBackWithRandomness(requestId, randomness, address(randProvider));
        gobblers.revealGobblers(numReveal);
    }
}
