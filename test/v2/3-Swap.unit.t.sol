// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./utils/BaseUnitTest.sol";

/// @dev Unit test suite for Swap behavior
contract SwapUnitTestv2 is BaseUnitTest {
    //

    /*//////////////////////////////////////////////////////////////
    //
    // Feature: User swaps with Goober
    //
    // As a Goober,
    // I want to swap Goo and/or Gobblers for Goo and/or Gobblers,
    // so that Z.
    //
    // Acceptance Criteria:
    // - Should be able to preview swap
    // - Should be able to swap Goo and/or Gobblers in exchange for Goo and/or Gobblers,
    //   with a potential surplus or deficit of erroneous Goo required to complete the swap
    // - Should be able to safe swap, which ensures a deadline after which the tx will revert,
    //   and a maximum amount of potential surplus or deficit of erroneous Goo required
    // - K Accounting: TODO (btw swap does not record kLast)
    // - TODO Should be able to flash swap, using any assets in the Goober vault for 1 tx, provided
    //   those assets can be deposited back plus swap fee on the amount withdrawn by the end of tx
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

    // TODO preview swap

    /*//////////////////////////////////////////////////////////////
    // Scenario: Swap Gobblers for Gobblers
    // Given Alice user mult is 23
    // When Alice swaps a Gobbler mult9 for a Gobbler mult7
    // Then Alice user mult should be 21
    // And Alice should receive TODO Goo
    //
    */

    function testSwap() public {
        // precondition
        assertEq(gobblers.getUserEmissionMultiple(alice), 23);

        gobblersOne = [1]; // Alice's mult9
        gobblersTwo = [5]; // Other's mult7

        vm.startPrank(alice);
        int256 expectedErroneousGoo = goober.previewSwap(gobblersOne, 0, gobblersTwo, 0);
        int256 actualErroneousGoo = goober.swap(gobblersOne, 0, gobblersTwo, 0, alice, "");

        assertEq(actualErroneousGoo, expectedErroneousGoo);
    }

    // TODO Gobblers for Goo
    // TODO Gobblers for Goo, Gobblers
    // TODO Goo for Goo
    // TODO Goo for Gobblers
    // TODO Goo for Goo, Gobblers
    // TODO Goo, Gobblers for Goo
    // TODO Goo, Gobblers for Gobblers
    // TODO Goo, Gobblers for Goo, Gobblers
    // TODO pluralize
    // TODO erroneous Goo positive, negative
    // TODO sad paths

    // TODO safe swap

    // TODO flash swap

    // TODO ETH swap
}
