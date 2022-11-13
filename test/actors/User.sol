// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./InvariantActor.sol";

/// @dev The User calls deposit, withdraw, and swap.
contract User is InvariantActor {
    uint256 public depositedGoo;
    uint256[] public depositedGobblers;

    uint256 public depositCalls;
    uint256 public withdrawCalls;
    uint256 public swapGobblersForGobblersCalls;
    uint256 public swapGooForGobblersCalls;
    uint256 public swapGobblersForGooCalls;

    constructor(
        Goober _goober,
        Goo _goo,
        ArtGobblers _gobblers,
        RandProvider _randProvider,
        VRFCoordinatorMock _vrfCoordinator
    ) InvariantActor(_goober, _goo, _gobblers, _randProvider, _vrfCoordinator) {}

    function getDepositedGobblers() external view returns (uint256[] memory) {
        return depositedGobblers;
    }

    function deposit(uint8 _gooTokens, uint8 _numGobblers) external {
        // convert _gooTokens to an amount between 10 and 2550 Goo.
        uint256 gooTokens = uint256(_gooTokens) * 10 ether;

        // convert _numGobblers to an amount between 0-10.
        uint256 numGobblers = _numGobblers % 11;

        // Draw gobblers from the pool
        uint256[] memory gobblersIn = _drawGobblers(numGobblers);

        // Mint ourselves Goo equal to the deposit amount
        _writeTokenBalance(address(this), address(goo), gooTokens);

        // Account for deposited goo and gobblers.
        for (uint256 i; i < gobblersIn.length; i++) {
            depositedGobblers.push(gobblersIn[i]);
        }
        depositedGoo += gooTokens;

        // Perform deposit
        goober.deposit(gobblersIn, gooTokens, address(this));
    }

    function withdraw(uint8 _gooNum, uint8 _gobblerNum) external {
        // Use _gooNum to calculate the proportion of deposited goo to withdraw.
        uint256 gooTokens = depositedGoo * uint256(_gooNum) / type(uint8).max;

        // Use _gobblerNum to calculate the proportion of deposited gobblers to withdraw.
        uint256 numGobblers = depositedGobblers.length * uint256(_gobblerNum) / type(uint8).max;

        // Remove gobblers from the depositedGobblers array.
        uint256[] memory gobblersOut = new uint256[](numGobblers);
        for (uint256 i; i < numGobblers; i++) {
            gobblersOut[i] = depositedGobblers[depositedGobblers.length - 1];
            depositedGobblers.pop();
        }
        // Account for withdrawn goo.
        depositedGoo -= gooTokens;

        // Return removed gobblers to the pool.
        _returnGobblers(gobblersOut);

        // Perform withdrawal
        goober.withdraw(gobblersOut, gooTokens, address(this), address(this));
    }

    function swapGobblersForGobblers(uint8 _swapGobblers, uint8 _poolGobblers) external {
        // Convert _swapGobblers to a number between 1-10.
        // Draw this many gobblers from the pool.
        uint256 swapGobblers = _swapGobblers % 10 + 1;
        uint256[] memory gobblersIn = _drawGobblers(swapGobblers);

        // Convert _poolGobblers to a number between 1-10
        uint256 poolGobblers = _poolGobblers % 10 + 1;

        // We can't swap for more gobblers than are in the Goober pool
        poolGobblers = poolGobblers > depositedGobblers.length ? depositedGobblers.length : poolGobblers;

        // Get the ids of gobblers we know are deposited
        uint256[] memory gobblersOut = new uint256[](poolGobblers);
        for (uint256 i; i < poolGobblers; i++) {
            gobblersOut[i] = depositedGobblers[depositedGobblers.length - 1];
            depositedGobblers.pop();
        }

        // Add the gobblers we're swapping to the depositedGobblers array
        for (uint256 i; i < swapGobblers; i++) {
            depositedGobblers.push(gobblersIn[i]);
        }

        // Preview the swap to determine how much Goo we need to provide.
        int256 erroneousGoo =
            goober.previewSwap({gobblersOut: gobblersOut, gooOut: 0, gobblersIn: gobblersIn, gooIn: 0});

        // If we need to provide more goo, mint it
        if (erroneousGoo > 0) {
            _writeTokenBalance(address(this), address(goo), uint256(erroneousGoo));
        }
        uint256 gooIn = (erroneousGoo > 0) ? uint256(erroneousGoo) : 0;

        // Perform the swap
        goober.swap({
            gobblersOut: gobblersOut,
            gooOut: 0,
            gobblersIn: gobblersIn,
            gooIn: gooIn,
            receiver: address(this),
            data: bytes("")
        });
    }

    function swapGobblersForGoo(uint8 _swapGobblers) external {
        // Convert _swapGobblers to a number between 1-10.
        // Draw this many gobblers from the pool.
        uint256 swapGobblers = _swapGobblers % 10 + 1;
        uint256[] memory gobblersIn = _drawGobblers(swapGobblers);

        // Push these gobblers in to the depositedGobblers array
        for (uint256 i; i < swapGobblers; i++) {
            depositedGobblers.push(gobblersIn[i]);
        }

        // No gobblersOut, since we are swapping for Goo only
        uint256[] memory gobblersOut = new uint256[](0);

        // Preview the swap to determine how much Goo we expect
        int256 erroneousGoo =
            goober.previewSwap({gobblersOut: gobblersOut, gooOut: 1, gobblersIn: gobblersIn, gooIn: 0});

        // erroneousGoo will be negative, convert to a positive amount
        uint256 gooOut = (erroneousGoo < 0) ? uint256(-1 * erroneousGoo) : 0;

        // Perform the swap
        goober.swap({
            gobblersOut: gobblersOut,
            gooOut: gooOut,
            gobblersIn: gobblersIn,
            gooIn: 0,
            receiver: address(this),
            data: bytes("")
        });
    }

    function swapGooForGobblers(uint8 _poolGobblers) external {
        // No gobblersIn for this swap.
        uint256[] memory gobblersIn = new uint256[](0);

        // Convert _poolGobblers to a number between 1-10
        uint256 poolGobblers = _poolGobblers % 10 + 1;

        // We can't swap for more gobblers than are in the Goober pool
        poolGobblers = poolGobblers > depositedGobblers.length ? depositedGobblers.length : poolGobblers;

        // Get the ids of gobblers we know are deposited
        uint256[] memory gobblersOut = new uint256[](poolGobblers);
        for (uint256 i; i < poolGobblers; i++) {
            gobblersOut[i] = depositedGobblers[depositedGobblers.length - 1];
            depositedGobblers.pop();
        }

        // Preview the swap to work out how much Goo we need to provide
        int256 erroneousGoo =
            goober.previewSwap({gobblersOut: gobblersOut, gooOut: 0, gobblersIn: gobblersIn, gooIn: 1});

        // Calculate gooIn based on the preview, and mint Goo to swap.
        if (erroneousGoo > 0) {
            _writeTokenBalance(address(this), address(goo), uint256(erroneousGoo));
        }
        uint256 gooIn = (erroneousGoo > 0) ? uint256(erroneousGoo) : 0;

        // Perform the swap
        goober.swap({
            gobblersOut: gobblersOut,
            gooOut: 0,
            gobblersIn: gobblersIn,
            gooIn: gooIn,
            receiver: address(this),
            data: bytes("")
        });
    }
}
