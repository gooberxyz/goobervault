// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./utils/BaseUnitTest.sol";

/// @dev Unit test suite for Withdraw behavior
contract WithdrawUnitTestv2 is BaseUnitTest {
    //

    /*//////////////////////////////////////////////////////////////
    //
    // Background: Starting balances and approvals
    //
    // Given Alice has 2000 Goo and 3 Gobblers (mult9, mult8, mult6)
    // And Bob has 2000 Goo and 1 Gobbler (mult9)
    // And Other has 2000 Goo and 2 Gobblers (mult6, mult7)
    // And Alice has approved Goober to spend her Goo and Gobblers
    // And Bob has approved Goober to spend his Goo and Gobblers
    // And Other deposits 1000 Goo and 2 Gobblers (mult6, mult7) into the Vault
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
