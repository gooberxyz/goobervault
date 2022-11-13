// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Fuzz tests for the Goober contracts

import "./utils/GooberTest.sol";

// TODO(Fuzz withdraw)
// TODO(Walk all paths and add assertions about balances)

contract GooberUnitTest is GooberTest {
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

    function testFuzzDeposit(uint112 gooDeposit, uint8 idx, bool multiGobbler, bool gooAndGobbler) public {
        _writeTokenBalance(users[1], address(goo), type(uint256).max - 1);
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
        goober.deposit(gobblersDeposit, 400 ether, users[1]);

        if (gooDeposit > type(uint104).max) {
            gooDeposit -= 401 ether;
        }

        uint256 previewFractions;
        uint256 actualFractions;
        if (gooAndGobbler) {
            if (multiGobbler) {
                previewFractions = goober.previewDeposit(gobblersWallet, gooDeposit);
                actualFractions = goober.deposit(gobblersWallet, gooDeposit, users[1]);
            } else {
                uint256[] memory gobblersWalletDeposit = new uint256[](1);
                gobblersWalletDeposit[0] = gobblersWallet[idx % 4];
                previewFractions = goober.previewDeposit(gobblersWalletDeposit, gooDeposit);
                actualFractions = goober.deposit(gobblersWalletDeposit, gooDeposit, users[1]);
            }
        } else {
            uint256[] memory noGobblerDeposit = new uint256[](0);
            // Only depositing 1 goo is unrealistic at this point
            if (gooDeposit < 7060343201) {
                vm.expectRevert("Goober: INSUFFICIENT_LIQUIDITY_MINTED");
                previewFractions = goober.previewDeposit(noGobblerDeposit, gooDeposit);
                vm.expectRevert("Goober: INSUFFICIENT_LIQUIDITY_MINTED");
                actualFractions = goober.deposit(noGobblerDeposit, gooDeposit, users[1]);
            } else {
                previewFractions = goober.previewDeposit(noGobblerDeposit, gooDeposit);
                actualFractions = goober.deposit(noGobblerDeposit, gooDeposit, users[1]);
            }
        }
        assertEq(previewFractions, actualFractions);
    }

    // TODO(Fuzz and fix deposit, which overflows over uint72)
    function testFuzzSwapAndPreview(
        uint72 gooIn,
        uint72 gooOut,
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

        // Deposit overflows at uint112 as expected
        goober.deposit(gobblersDeposit, type(uint80).max, users[1]);

        SwapParams memory params = SwapParams(gobblersDeposit, gooIn, gobblersWallet, gooOut, msg.sender, "");

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
                        vm.expectRevert("Goober: INSUFFICIENT_INPUT_AMOUNT");
                        goober.previewSwap(gobblerIn, params.gooIn, gobblerOut, params.gooOut);
                        vm.expectRevert("Goober: INSUFFICIENT_INPUT_AMOUNT");
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