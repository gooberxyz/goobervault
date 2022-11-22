// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./utils/BaseUnitTest.sol";

/// @dev Unit test suite for Fee assessment behavior
contract FeesUnitTestv2 is BaseUnitTest {
    //

    /*//////////////////////////////////////////////////////////////
    //
    // Feature: Protocol assesses fees on user actions
    //
    // As the Protocol Admin,
    // we want the Protocol to automatically assess fees on user actions,
    // so that we can continue to develop Goober and provide value to the Art Gobblers community.
    //
    // Acceptance Criteria:
    // - Deposit fee of 2% should be assessed on all deposits, recorded de facto in kLast
    // - Withdraw fee of 2% should be assessed on all withdraws, recorded de facto in kLast
    // - Swap fee of 2% should be assessed on all swaps, recorded de facto in kLast
    // - Performance fee of 10% should be assessed on all actions, if the growth in K since
    //   kLast is sufficient to offset any accrued kDebt, paid in GBR to Protocol Admin address
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

    function testTrue() public {
        assertTrue(true);
    }
}
