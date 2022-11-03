// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "../src/interfaces/IERC20Metadata.sol";
import "../src/Goober.sol";
import "openzeppelin-contracts-upgradeable/proxy/ERC1967/ERC1967UpgradeUpgradeable.sol";

contract TestUERC20Functionality is Test {
    using stdStorage for StdStorage;

    // Test Contracts
    Goober public goober_implementation;
    ERC1967UpgradeUpgradeable public goober_proxy;

    function setUp() public {
        goober_implementation = new Goober();
        goober_proxy = new ERC1967UpgradeUpgradeable(address(goober_implementation),  abi.encodeWithSignature("initialize()"));
    }

    function test_proxy() public {
        // Assertions
        assertEq(IERC20Metadata(address(goober_proxy)).name(), "Goober");
        assertEq(IERC20Metadata(address(goober_proxy)).symbol(), "GBR");
        assertEq(IERC20Metadata(address(goober_proxy)).decimals(), 18);
    }
}
