// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "art-gobblers/Goo.sol";
import "art-gobblers/ArtGobblers.sol";
import "../src/Goober.sol";

contract TestUERC20Functionality is Test {
    using stdStorage for StdStorage;

    // Test Contracts
    Goober public goober_implementation;
    TransparentUpgradeableProxy public goober_proxy;

    // Art gobbler stuff
    Goo public constant goo = Goo(0x600000000a36F3cD48407e35eB7C5c910dc1f7a8);
    ArtGobblers public constant artGobblers = ArtGobblers(0x60bb1e2AA1c9ACAfB4d34F71585D7e959f387769);

    function setUp() public {
        goober_implementation = new Goober();
        goober_proxy =
        new TransparentUpgradeableProxy(address(goober_implementation), address(msg.sender), abi.encodeWithSignature("initialize()"));
        goo.approve(address(goober_proxy), type(uint256).max);
    }

    function test_proxy() public {
        // Assertions
        assertEq(IERC20Metadata(address(goober_proxy)).name(), "Goober");
        assertEq(IERC20Metadata(address(goober_proxy)).symbol(), "GBR");
        assertEq(IERC20Metadata(address(goober_proxy)).decimals(), 18);
    }

}
