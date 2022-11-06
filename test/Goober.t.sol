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

    function testSkimGoo() public {
      // vm.prank(GOO_WHALE); //WALLET HAS MULTIPLE GOBBLERS
      vm.startPrank(GOO_WHALE); //Last check has 281348557198281598718
      // assertGt( (GOO_WHALE).balance,0); //WALLET NOW HAS 1 WEI
      assertGt(goo.balanceOf(GOO_WHALE), 0);
      goo.transfer(address(this),1);
      assertEq(goo.balanceOf(address(this)), 1);
      // goo.transfer(address(this),0);

      vm.stopPrank();

      // assertEq(address(goo), address(goo));
      // fail("FAIL");
      // emit log("here");

      deal(msg.sender, 1); //1 WEI ETH
      assertGt( (msg.sender).balance,0); //WALLET NOW HAS 1 WEI
      // assertEq( (msg.sender).balance,1); //WALLET NOW HAS 1 WEI


      // deal(address(goo), msg.sender, 1); //1 WEI
      // assertEq(goo.balanceOf(msg.sender, 1));

      // assertEq(goo.balanceOf(msg.sender, 1));
      // assertEq(goo.balanceOf(address(this)), 770227215730798173166);
      // goo.approve(address(goober_implementation), type(uint256).max);
      // goo.transferFrom(GOO_WHALE,address(this),1);
      // assertEq(goo.balanceOf(address(this)), 1);
      // vm.prank(msg.sender); //WALLET HAS MULTIPLE GOBBLERS
      // // uint ownerBalanceBeforeSkim = goo.balanceOf(msg.sender)
      // goober_implementation.skimGoo();
      // assertEq(goo.balanceOf(msg.sender), 1);
    }

    function testSkimGobblerTest() public {
      vm.prank(GOBBLER_WHALE); //WALLET HAS MULTIPLE GOBBLERS
      // artGobblers.transferFrom(msg.sender,address(this),1937);
      // assertEq(artGobblers.ownerOf(1937), address(this));
      // vm.prank(msg.sender); //WALLET HAS MULTIPLE GOBBLERS
      // goober_implementation.skimGobbler(1937);
      // assertEq(artGobblers.ownerOf(1937), msg.sender);
    }

}
