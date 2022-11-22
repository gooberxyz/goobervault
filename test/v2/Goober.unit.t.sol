// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./utils/BaseUnitTest.sol";

contract InitialUnitTestv2 is BaseUnitTest {
    //
    function testInitial() public {
        assertEq(goober.name(), "Goober");
        assertEq(goober.symbol(), "GBR");
        assertEq(goober.decimals(), 18);

        assertEq(address(goober.goo()), address(goo));
        assertEq(address(goober.artGobblers()), address(gobblers));

        assertEq(goober.feeTo(), FEE_TO);
        assertEq(goober.minter(), MINTER);
    }
}
