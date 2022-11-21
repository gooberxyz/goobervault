// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../utils/GooberTest.sol";

contract UnitDepositWithdrawTestv2 is GooberTest {
    //
    address internal alice;
    address internal bob;

    uint256[] internal gobblersOne;
    uint256[] internal gobblersTwo;
    uint256[] internal gobblersThree;

    function setUp() public override {
        super.setUp();

        // Setup 10 users with 2000 Goo and approve vault to spend their Goo + Gobblers
        for (uint256 i = 0; i < 10; i++) {
            _writeTokenBalance(users[i], address(goo), START_BAL);

            vm.startPrank(users[i]);
            goo.approve(address(goober), type(uint256).max);
            gobblers.setApprovalForAll(address(goober), true);
            vm.stopPrank();
        }

        // Alice mints 3 Gobblers, Bob mints 1 Gobbler
        alice = users[0];
        bob = users[1];
        vm.startPrank(alice);
        gobblers.addGoo(500 ether);
        gobblers.mintFromGoo(100 ether, true);
        gobblers.mintFromGoo(100 ether, true);
        gobblers.mintFromGoo(100 ether, true);
        vm.stopPrank();
        vm.startPrank(bob);
        gobblers.addGoo(500 ether);
        gobblers.mintFromGoo(100 ether, true);
        vm.stopPrank();
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(1, "seed");
    }

    // Background: Starting balances and approvals
    // Given Alice has 2000 Goo and 3 Gobblers
    // And Bob has 2000 Goo and 1 Gobbler
    // And Alice has approved Goober to spend her Goo and Gobblers
    // And Bob has approved Goober to spend his Goo and Gobblers

    /*//////////////////////////////////////////////////////////////
    //  Deposit
    //////////////////////////////////////////////////////////////*/

    // Scenario: Preview deposit
    // When Alice previews a deposit
    // Then Alice should see TODO Goober as the amount of fractions she would receive

    function testPreviewDeposit() public {
        gobblersOne = new uint256[](1);
        gobblersOne[0] = 1; // tokenID 1

        vm.prank(alice);
        uint256 fractions = goober.previewDeposit(gobblersOne, 500 ether);

        assertEq(fractions, 65740398537519999020);
    }
}
