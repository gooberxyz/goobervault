// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./BaseGooberTest.sol";

abstract contract BaseUnitTest is BaseGooberTest {
    //
    address internal alice;
    address internal bob;

    uint256[] internal gobblersZero;
    uint256[] internal gobblersOne;
    uint256[] internal gobblersTwo;
    uint256[] internal gobblersThree;
    uint256[] internal gobblersEmpty = new uint256[](0);

    function setUp() public override {
        super.setUp();

        // Setup 10 users with 2000 Goo and approve vault to spend their Goo + Gobblers
        for (uint256 i = 0; i < 10; i++) {
            _writeTokenBalance(users[i], address(goo), START_BAL);

            vm.startPrank(users[i]);
            goo.approve(address(goober), type(uint256).max);
            gobblers.setApprovalForAll(address(goober), true);
            vm.stopPrank();
        }

        // Alice mints 3 Gobblers, Bob mints 1 Gobbler
        alice = users[0];
        bob = users[1];
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.startPrank(alice);
        gobblers.addGoo(500 ether);
        gobblers.mintFromGoo(100 ether, true);
        gobblers.mintFromGoo(100 ether, true);
        gobblers.mintFromGoo(100 ether, true);
        vm.stopPrank();
        vm.startPrank(bob);
        gobblers.addGoo(500 ether);
        gobblers.mintFromGoo(100 ether, true);
        vm.stopPrank();
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(4, "seed");

        // Other user mints 2 Gobblers
        vm.startPrank(users[2]);
        gobblers.addGoo(500 ether);
        gobblers.mintFromGoo(100 ether, true);
        gobblers.mintFromGoo(100 ether, true);
        vm.warp(TIME0 + 2 days);
        _setRandomnessAndReveal(2, "dees");

        // Other deposits 1000 Goo and 2 Gobblers into Vault
        gobblersZero = new uint256[](2);
        gobblersZero[0] = 5;
        gobblersZero[1] = 6;
        goober.deposit(gobblersZero, 1000 ether, users[2]);
        vm.stopPrank();
    }
}
