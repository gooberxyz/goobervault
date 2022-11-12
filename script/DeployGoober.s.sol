// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import "../src/Goober.sol";

contract DeployGooberScript is Script {
  function run() public {
    vm.startBroadcast();

    ArtGobblers artGobblers = ArtGobblers(
      0x60bb1e2AA1c9ACAfB4d34F71585D7e959f387769
    );
    IERC20 goo = IERC20(0x600000000a36F3cD48407e35eB7C5c910dc1f7a8);

    Goober goober = new Goober(
      address(artGobblers), // Art Gobblers
      address(goo), // GOO
      0x70997970C51812dc3A010C7d01b50e0d17dc79C8,
      0x70997970C51812dc3A010C7d01b50e0d17dc79C8
    );

    goo.approve(address(goober), 1000000000000000000);

    artGobblers.setApprovalForAll(address(goober), true);

    uint256[] memory gobblers = new uint256[](1);
    gobblers[0] = 1002;

    goober.deposit(
      gobblers,
      1000000000000000000,
      0x70997970C51812dc3A010C7d01b50e0d17dc79C8
    );

    vm.stopBroadcast();
  }
}
