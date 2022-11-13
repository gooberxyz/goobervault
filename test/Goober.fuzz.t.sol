// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Fuzz tests for the Goober contracts

import "./utils/GooberTest.sol";

// TODO(Walk all paths and add assertions about balances)

contract GooberFuzzTest is GooberTest {
    function setUp() public override {
        super.setUp();

        // Setup balances and approvals
        for (uint256 i = 1; i < 11; i++) {
            _writeTokenBalance(users[i], address(goo), START_BAL);

            vm.startPrank(users[i]);
            goo.approve(address(goober), type(uint256).max);
            gobblers.setApprovalForAll(address(goober), true);
            vm.stopPrank();
        }
    }

    function testFuzzDepositWithdrawAndPreview(uint104 gooDeposit, uint8 idx, bool multiGobbler, bool gooAndGobbler)
        public
    {
        _writeTokenBalance(users[1], address(goo), type(uint128).max - 1);
        vm.startPrank(users[1]);
        gobblers.addGoo(800 ether);

        // Gobblers to deposit
        uint256[] memory gobblersDeposit = new uint256[](4);
        gobblersDeposit[0] = gobblers.mintFromGoo(100 ether, true);
        gobblersDeposit[1] = gobblers.mintFromGoo(100 ether, true);
        gobblersDeposit[2] = gobblers.mintFromGoo(100 ether, true);
        gobblersDeposit[3] = gobblers.mintFromGoo(100 ether, true);

        vm.warp(block.timestamp + 1 days);
        _setRandomnessAndReveal(4, "FirstSeed");

        // Gobblers to deposit
        uint256[] memory gobblersWallet = new uint256[](4);
        gobblersWallet[0] = gobblers.mintFromGoo(100 ether, true);
        gobblersWallet[1] = gobblers.mintFromGoo(100 ether, true);
        gobblersWallet[2] = gobblers.mintFromGoo(100 ether, true);
        gobblersWallet[3] = gobblers.mintFromGoo(110 ether, true);

        vm.warp(block.timestamp + 1 days);
        _setRandomnessAndReveal(4, "SecondSeed");

        // Mint minimum liquidity to rule out edge cases that are documented
        // Account for withdraws
        uint256 initial = 1 ether + (uint256(gooDeposit) * 103 - uint256(gooDeposit) * 100);
        goober.deposit(gobblersDeposit, initial, users[1]);

        if (gooDeposit > type(uint104).max) {
            gooDeposit = type(uint104).max;
        }

        uint256 previewFractionsDeposit;
        uint256 actualFractionsDeposit;
        uint256 previewFractionsWithdraw;
        uint256 actualFractionsWithdraw;
        if (gooAndGobbler) {
            if (multiGobbler) {
                previewFractionsDeposit = goober.previewDeposit(gobblersWallet, gooDeposit);
                actualFractionsDeposit = goober.deposit(gobblersWallet, gooDeposit, users[1]);
                previewFractionsWithdraw = goober.previewWithdraw(gobblersWallet, gooDeposit);
                actualFractionsWithdraw = goober.withdraw(gobblersWallet, gooDeposit, users[1], users[1]);
            } else {
                uint256[] memory gobblersWalletDeposit = new uint256[](1);
                gobblersWalletDeposit[0] = gobblersWallet[idx % 4];
                previewFractionsDeposit = goober.previewDeposit(gobblersWalletDeposit, gooDeposit);
                actualFractionsDeposit = goober.deposit(gobblersWalletDeposit, gooDeposit, users[1]);
                previewFractionsWithdraw = goober.previewWithdraw(gobblersWalletDeposit, gooDeposit);
                actualFractionsWithdraw = goober.withdraw(gobblersWalletDeposit, gooDeposit, users[1], users[1]);
            }
        } else {
            uint256[] memory noGobblerDeposit = new uint256[](0);
            // Only depositing 1 goo is unrealistic at this point
            if (gooDeposit == 0) {
                vm.expectRevert(IGoober.InsufficientLiquidityDeposited.selector);
                previewFractionsDeposit = goober.previewDeposit(noGobblerDeposit, gooDeposit);
                vm.expectRevert(IGoober.InsufficientLiquidityDeposited.selector);
                actualFractionsDeposit = goober.deposit(noGobblerDeposit, gooDeposit, users[1]);
                vm.expectRevert(IGoober.InsufficientLiquidityWithdrawn.selector);
                previewFractionsWithdraw = goober.previewWithdraw(noGobblerDeposit, gooDeposit);
                vm.expectRevert(IGoober.InsufficientLiquidityWithdrawn.selector);
                actualFractionsWithdraw = goober.withdraw(noGobblerDeposit, gooDeposit, users[1], users[1]);
            } else if (gooDeposit > 1 ether) {
                // Otherwise depends on specifics
                previewFractionsDeposit = goober.previewDeposit(noGobblerDeposit, gooDeposit);
                actualFractionsDeposit = goober.deposit(noGobblerDeposit, gooDeposit, users[1]);
                previewFractionsWithdraw = goober.previewWithdraw(noGobblerDeposit, gooDeposit);
                actualFractionsWithdraw = goober.withdraw(noGobblerDeposit, gooDeposit, users[1], users[1]);
            }
        }
        assertEq(previewFractionsDeposit, actualFractionsDeposit);
        assertEq(previewFractionsWithdraw, actualFractionsWithdraw);
    }

    // Not feasible to test here above uint96 because the fuzz starts hitting over/underflow a lot.
    function testFuzzSwapAndPreview(
        uint96 gooIn,
        uint96 gooOut,
        uint8 idx,
        bool multiGobbler,
        bool gobblerGobbler,
        bool gobblerInOut
    ) public {
        _writeTokenBalance(users[1], address(goo), type(uint112).max);
        vm.startPrank(users[1]);
        gobblers.addGoo(800 ether);

        // Gobblers to deposit
        uint256[] memory gobblersDeposit = new uint256[](4);
        gobblersDeposit[0] = gobblers.mintFromGoo(100 ether, true);
        gobblersDeposit[1] = gobblers.mintFromGoo(100 ether, true);
        gobblersDeposit[2] = gobblers.mintFromGoo(100 ether, true);
        gobblersDeposit[3] = gobblers.mintFromGoo(100 ether, true);

        vm.warp(block.timestamp + 1 days);
        _setRandomnessAndReveal(4, "FirstSeed");

        // Gobblers to deposit
        uint256[] memory gobblersWallet = new uint256[](4);
        gobblersWallet[0] = gobblers.mintFromGoo(100 ether, true);
        gobblersWallet[1] = gobblers.mintFromGoo(100 ether, true);
        gobblersWallet[2] = gobblers.mintFromGoo(100 ether, true);
        gobblersWallet[3] = gobblers.mintFromGoo(110 ether, true);

        vm.warp(block.timestamp + 1 days);
        _setRandomnessAndReveal(4, "SecondSeed");

        SwapParams memory params = SwapParams(gobblersDeposit, gooIn, gobblersWallet, gooOut, msg.sender, "");

        goober.deposit(params.gobblersOut, type(uint104).max, users[1]);

        // Gobbler in
        if (multiGobbler) {
            int256 previewAdditionalGooRequired =
                goober.previewSwap(params.gobblersIn, params.gooIn, params.gobblersOut, params.gooOut);
            if (previewAdditionalGooRequired < 0) {
                assertEq(
                    goober.swap(
                        params.gobblersIn,
                        params.gooIn,
                        params.gobblersOut,
                        params.gooOut + uint256(-previewAdditionalGooRequired),
                        users[1],
                        params.data
                    ),
                    int256(0)
                );
            } else if (previewAdditionalGooRequired > 0) {
                assertEq(
                    goober.swap(
                        params.gobblersIn,
                        params.gooIn + uint256(previewAdditionalGooRequired),
                        params.gobblersOut,
                        params.gooOut,
                        users[1],
                        params.data
                    ),
                    int256(0)
                );
            } else {
                assertEq(
                    goober.swap(
                        params.gobblersIn, params.gooIn, params.gobblersOut, params.gooOut, users[1], params.data
                    ),
                    int256(0)
                );
            }
        } else {
            if (gobblerGobbler) {
                uint256[] memory gobblerIn = new uint256[](1);
                gobblerIn[0] = gobblersWallet[idx % 4];

                uint256[] memory gobblerOut = new uint256[](1);
                gobblerOut[0] = gobblersDeposit[idx % 4];

                int256 previewAdditionalGooRequired =
                    goober.previewSwap(gobblerIn, params.gooIn, gobblerOut, params.gooOut);
                if (previewAdditionalGooRequired < 0) {
                    assertEq(
                        goober.swap(
                            gobblerIn,
                            params.gooIn,
                            gobblerOut,
                            params.gooOut + uint256(-previewAdditionalGooRequired),
                            users[1],
                            params.data
                        ),
                        int256(0)
                    );
                } else if (previewAdditionalGooRequired > 0) {
                    assertEq(
                        goober.swap(
                            gobblerIn,
                            params.gooIn + uint256(previewAdditionalGooRequired),
                            gobblerOut,
                            params.gooOut,
                            users[1],
                            params.data
                        ),
                        int256(0)
                    );
                } else {
                    assertEq(
                        goober.swap(gobblerIn, params.gooIn, gobblerOut, params.gooOut, users[1], params.data),
                        int256(0)
                    );
                }
            } else {
                if (gobblerInOut) {
                    uint256[] memory gobblerIn = new uint256[](1);
                    gobblerIn[0] = gobblersWallet[idx % 4];

                    uint256[] memory gobblerOut = new uint256[](0);

                    int256 previewAdditionalGooRequired =
                        goober.previewSwap(gobblerIn, params.gooIn, gobblerOut, params.gooOut);
                    if (previewAdditionalGooRequired < 0) {
                        assertEq(
                            goober.swap(
                                gobblerIn,
                                params.gooIn,
                                gobblerOut,
                                params.gooOut + uint256(-previewAdditionalGooRequired),
                                users[1],
                                params.data
                            ),
                            int256(0)
                        );
                    } else if (previewAdditionalGooRequired > 0) {
                        assertEq(
                            goober.swap(
                                gobblerIn,
                                params.gooIn + uint256(previewAdditionalGooRequired),
                                gobblerOut,
                                params.gooOut,
                                users[1],
                                params.data
                            ),
                            int256(0)
                        );
                    } else {
                        assertEq(
                            goober.swap(gobblerIn, params.gooIn, gobblerOut, params.gooOut, users[1], params.data),
                            int256(0)
                        );
                    }
                } else {
                    uint256[] memory gobblerIn = new uint256[](0);

                    uint256[] memory gobblerOut = new uint256[](1);
                    gobblerOut[0] = gobblersDeposit[idx % 4];

                    if (params.gooIn == 0) {
                        (uint256 gooReserve, uint256 gobblerReserve,) = goober.getReserves();
                        vm.expectRevert(abi.encodeWithSelector(IGoober.InsufficientInputAmount.selector, 0, 0));
                        goober.previewSwap(gobblerIn, params.gooIn, gobblerOut, params.gooOut);
                        vm.expectRevert(abi.encodeWithSelector(IGoober.InsufficientInputAmount.selector, 0, 0));
                        goober.swap(gobblerIn, params.gooIn, gobblerOut, params.gooOut, users[1], params.data);
                    } else {
                        int256 previewAdditionalGooRequired =
                            goober.previewSwap(gobblerIn, params.gooIn, gobblerOut, params.gooOut);
                        if (previewAdditionalGooRequired < 0) {
                            assertEq(
                                goober.swap(
                                    gobblerIn,
                                    params.gooIn,
                                    gobblerOut,
                                    params.gooOut + uint256(-previewAdditionalGooRequired),
                                    users[1],
                                    params.data
                                ),
                                int256(0)
                            );
                        } else if (previewAdditionalGooRequired > 0) {
                            assertEq(
                                goober.swap(
                                    gobblerIn,
                                    params.gooIn + uint256(previewAdditionalGooRequired),
                                    gobblerOut,
                                    params.gooOut,
                                    users[1],
                                    params.data
                                ),
                                int256(0)
                            );
                        } else {
                            assertEq(
                                goober.swap(gobblerIn, params.gooIn, gobblerOut, params.gooOut, users[1], params.data),
                                int256(0)
                            );
                        }
                    }
                }
            }
        }
        vm.stopPrank();
    }
}
