// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../utils/GooberTest.sol";

contract UnitDepositWithdrawTestv2 is GooberTest {
    //
    address internal alice;
    address internal bob;

    uint256[] internal gobblersZero;
    uint256[] internal gobblersOne;
    uint256[] internal gobblersTwo;
    uint256[] internal gobblersThree;
    uint256[] internal gobblersEmpty = new uint256[](0);

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
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
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
        _setRandomnessAndReveal(4, "seed");

        // Other user mints 2 Gobblers
        vm.startPrank(users[2]);
        gobblers.addGoo(500 ether);
        gobblers.mintFromGoo(100 ether, true);
        gobblers.mintFromGoo(100 ether, true);
        vm.warp(TIME0 + 2 days);
        _setRandomnessAndReveal(2, "dees");

        // Other deposits 1000 Goo and 2 Gobblers into Vault
        gobblersZero = new uint256[](2);
        gobblersZero[0] = 5;
        gobblersZero[1] = 6;
        goober.deposit(gobblersZero, 1000 ether, users[2]);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
    // Background: Starting balances and approvals
    // Given Alice has 2000 Goo and 3 Gobblers (mult9, mult8, mult6)
    // And Bob has 2000 Goo and 1 Gobbler (mult9)
    // And Other has 2000 Goo and 2 Gobblers (mult6, mult7)
    // And Alice has approved Goober to spend her Goo and Gobblers
    // And Bob has approved Goober to spend his Goo and Gobblers
    // And Other deposits 1000 Goo and 2 Gobblers (mult6, mult7) into the Vault
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
    //  DEPOSIT
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
    // Scenario: Preview deposit
    // When Alice previews a deposit of 500 Goo and 1 Gobbler mult9
    // Then Alice should see TODO GBR as the amount of fractions to be minted
    //////////////////////////////////////////////////////////////*/

    function testPreviewDeposit() public {
        gobblersOne = [1]; // tokenID 1

        vm.prank(alice);
        uint256 fractionsToMint = goober.previewDeposit(gobblersOne, 500 ether);

        assertEq(fractionsToMint, 66288649161279999462);
    }

    // TODO sad paths

    /*//////////////////////////////////////////////////////////////
    // Scenario: Deposit Goo and Gobblers
    // When Alice deposits 500 Goo and 1 Gobbler mult9
    // Then Alice should mint TODO GBR fractions
    //////////////////////////////////////////////////////////////*/

    function testDeposit() public {
        gobblersOne = [1];

        vm.startPrank(alice);
        uint256 expected = goober.previewDeposit(gobblersOne, 500 ether);
        uint256 fractionsMinted = goober.deposit(gobblersOne, 500 ether, alice);
        vm.stopPrank();

        assertEq(fractionsMinted, expected);
    }

    // TODO just Goo, just Gobblers
    // TODO sad paths

    /*//////////////////////////////////////////////////////////////
    // Scenario: Safe deposit Goo
    // When Alice safe deposits 500 Goo and 1 Gobbler mult9, with TODO min fractions and TODO deadline
    // Then Alice should mint TODO GBR fractions
    //////////////////////////////////////////////////////////////*/

    function testSafeDeposit() public {
        gobblersOne = [1];

        vm.startPrank(alice);
        uint256 expected = goober.previewDeposit(gobblersOne, 500 ether);
        uint256 fractionsMinted = goober.safeDeposit(gobblersOne, 500 ether, alice, expected, block.timestamp);
        vm.stopPrank();

        assertEq(fractionsMinted, expected);
    }

    // TODO just Goo, just Gobblers
    // TODO with other receiver
    // TODO sad paths

    /*//////////////////////////////////////////////////////////////
    //  WITHDRAW
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
    // Scenario: Preview withdraw
    // Given Alice deposits 500 Goo and 1 Gobbler mult9
    // When Alice previews withdraw of 500 Goo and 1 Gobbler mult9
    // Then Alice should see TODO Goober as the amount of fractions to be burned
    //////////////////////////////////////////////////////////////*/

    function testPreviewWithdraw() public {
        gobblersOne = [1];

        vm.startPrank(alice);
        goober.deposit(gobblersOne, 500 ether, alice);
        uint256 fractionsToBurn = goober.previewWithdraw(gobblersOne, 500 ether);
        vm.stopPrank();

        assertEq(fractionsToBurn, 67641478735999999464);
    }

    // TODO sad paths

    /*//////////////////////////////////////////////////////////////
    // Scenario: Withdraw Goo
    // Given Alice deposits 500 Goo and 1 Gobbler mult9
    // When Alice withdraws 500 Goo
    // Then Alice should burn TODO GBR fractions
    //////////////////////////////////////////////////////////////*/

    function testWithdrawGoo() public {
        gobblersOne = [1];

        vm.startPrank(alice);
        goober.deposit(gobblersOne, 500 ether, alice);
        uint256 expected = goober.previewWithdraw(gobblersEmpty, 500 ether);
        uint256 fractionsBurned = goober.withdraw(gobblersEmpty, 500 ether, alice, alice);
        vm.stopPrank();

        assertEq(fractionsBurned, expected);
    }

    // TODO Goo and Gobblers, just Gobblers
    // TODO with other receiver, with other owner
    // TODO sad paths

    /*//////////////////////////////////////////////////////////////
    // Scenario: Safe withdraw Goo
    // Given Alice deposits 500 Goo and 1 Gobbler mult9
    // When Alice safe withdraws 500 Goo, with TODO min fractions and TODO deadline
    // Then Alice should burn TODO GBR fractions
    //////////////////////////////////////////////////////////////*/

    function testSafeWithdrawGoo() public {
        gobblersOne = [1];

        vm.startPrank(alice);
        goober.deposit(gobblersOne, 500 ether, alice);
        uint256 expected = goober.previewWithdraw(gobblersEmpty, 500 ether);
        uint256 fractionsBurned = goober.safeWithdraw(gobblersEmpty, 500 ether, alice, alice, expected, block.timestamp);
        vm.stopPrank();

        assertEq(fractionsBurned, expected);
    }

    // TODO Goo and Gobblers, just Gobblers
    // TODO with other receiver, with other owner
    // TODO sad paths

}
