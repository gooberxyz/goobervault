// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./utils/BaseUnitTest.sol";

contract SwapUnitTestv2 is BaseUnitTest {
    //

    /*//////////////////////////////////////////////////////////////
    // Background: Starting balances and approvals
    // Given Alice has 2000 Goo and 3 Gobblers (mult9, mult8, mult6)
    // And Bob has 2000 Goo and 1 Gobbler (mult9)
    // And Other has 2000 Goo and 2 Gobblers (mult6, mult7)
    // And Alice has approved Goober to spend her Goo and Gobblers
    // And Bob has approved Goober to spend his Goo and Gobblers
    // And Other deposits 1000 Goo and 2 Gobblers (mult7, mult6) into the Vault
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
    //  SWAP
    //////////////////////////////////////////////////////////////*/

    // TODO preview swap

    /*//////////////////////////////////////////////////////////////
    // Scenario: Swap Gobblers for Gobblers
    // Given Alice user mult is 23
    // When Alice swaps a Gobbler mult9 for a Gobbler mult7
    // Then Alice user mult should be 21
    // And Alice should receive TODO Goo
    //////////////////////////////////////////////////////////////*/

    // TODO preview swap

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
}
