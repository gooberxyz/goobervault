// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

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
    // Acceptance Criteria: TODO simplify based on latest
    // - Liquidity Fee of 1% should be assessed on deposits, withdraws, and swaps
    // - Liquidity Fee on deposits is assessed by storing a kLast value that is 1% greater than actual
    // - Liquidity Fee on withdraws is assessed by storing a kLast value that is 1% less than actual
    // - Liquidity Fee on swaps is assessed by requiring 1% more Goo in, based on net Goo/Mult in and Goo/Mult out (and kLast is not updated btw)
    // - Performance Fee of 10% should be assessed on deposits and withdraws if kNew is greater than kLast
    // - Performance Fee is assessed by minting GBR fractions to Protocol Admin address
    // - Performance Fee should not be assessed on initial deposit, as the pool is uninitialized
    // - There should be immutable maximum values for Liquidity Fee of 2% and Performance Fee of 10%
    // - Protocol Admin should be able to update any of the 4 fees, which then slow-grow over
    //   the next 7 days, taking into account any currently active slow-grow fee updates
    // - TODO Minting strategy and kDebt accounting



    // - On deposits and withdraws, Liquidity Fee is assessed de facto in kLast by reducing its value
    // - Swap fee of 1% should be assessed on all swaps, requiring 1% more Goo in, based on your net Goo/Gobblers in and out (and btw kLast nor kDebt is updated)
    // - Performance fee of 10% should be assessed on deposit and withdraw, if the growth in K since
    //   kLast is sufficient to offset any accrued kDebt, paid in GBR to Protocol Admin address
    // - K accounting TODO
            - k
            - kLast
            - kDebt (including impact on Deposit and Withdraw for the LPs,
    //      otherwise bonusing depositors and penalizing withdrawers)
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
