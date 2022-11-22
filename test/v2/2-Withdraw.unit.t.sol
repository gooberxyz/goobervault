// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./utils/BaseUnitTest.sol";

/// @dev Unit test suite for Withdraw behavior
contract WithdrawUnitTestv2 is BaseUnitTest {
    //

    /*//////////////////////////////////////////////////////////////
    //
    // Feature: User withdraws from Goober
    //
    // As a Goober,
    // I want to withdraw my Goo and/or Gobblers,
    // so that I can realize some of the Goo my Goober fractions have produced.
    //
    // Acceptance Criteria:
    // - Should be able to preview withdraw
    // - Should be able to withdraw Goo and/or Gobblers in exchange for burning GBR vault fractions
    // - Should be able to safe withdraw, which ensures a deadline after which the tx will revert,
    //   and maximum amount of GBR fractioned to be burned
    //
    // Background: Starting balances and approvals (same for all unit tests)
    //
    // Given Alice, Bob, Carol, and Dave each have 2000 Goo
    // And Alice mints 3 Gobblers (mult9, mult8, mult6)
    // And Bob mints 1 Gobbler (mult9)
    // And Carol mints 2 Gobblers (mult6, mult7)
    // And Dave mints 0 Gobblers
    // And Alice, Bob, Carol, and Dave have approved Goober to spend their Goo and Gobblers
    // And Carol deposits 1000 Goo and 2 Gobblers (mult6, mult7) into Goober
    //
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
    //
    // Scenario: Preview withdraw
    //
    // Given Alice deposits 500 Goo and 1 Gobbler mult9
    // When Alice previews withdraw of 500 Goo and 1 Gobbler mult9
    // Then Alice should see TODO Goober as the amount of fractions to be burned
    //
    */

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
    //
    // Scenario: Withdraw Goo
    //
    // Given Alice deposits 500 Goo and 1 Gobbler mult9
    // When Alice withdraws 500 Goo
    // Then Alice should burn TODO GBR fractions
    //
    */

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
    //
    // Scenario: Safe withdraw Goo
    //
    // Given Alice deposits 500 Goo and 1 Gobbler mult9
    // When Alice safe withdraws 500 Goo, with TODO min fractions and TODO deadline
    // Then Alice should burn TODO GBR fractions
    //
    */

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
