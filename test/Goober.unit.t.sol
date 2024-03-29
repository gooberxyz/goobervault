// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./utils/GooberTest.sol";

// TODO write event tests
// TODO write tests for single/multiple deposit, withdraw, swap happy paths
// TODO write tests to cover all require cases, then refactor into custom errors

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

    function testUnitInitial() public {
        assertEq(goober.name(), "Goober");
        assertEq(goober.symbol(), "GBR");
        assertEq(goober.decimals(), 18);

        assertEq(address(goober.goo()), address(goo));
        assertEq(address(goober.artGobblers()), address(gobblers));

        assertEq(goober.feeTo(), FEE_TO);
        assertEq(goober.minter(), MINTER);
    }

    function testUnitSetRandomnessAndRevealHelper() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);
        gobblers.mintFromGoo(100 ether, true);
        gobblers.mintFromGoo(100 ether, true);
        gobblers.mintFromGoo(100 ether, true);

        // Reveal 3 at once
        vm.warp(TIME0 + 1 days);

        _setRandomnessAndReveal(3, "seed");

        assertEq(gobblers.getGobblerEmissionMultiple(1), 9);
        assertEq(gobblers.getGobblerEmissionMultiple(2), 8);
        assertEq(gobblers.getGobblerEmissionMultiple(3), 6);

        // Reveal one at a time
        gobblers.addGoo(500 ether);
        gobblers.mintFromGoo(100 ether, true);
        vm.warp(block.timestamp + 1 days);
        _setRandomnessAndReveal(1, "seed");
        assertEq(gobblers.getGobblerEmissionMultiple(1), 9);

        gobblers.addGoo(500 ether);
        gobblers.mintFromGoo(100 ether, true);
        vm.warp(block.timestamp + 1 days);
        _setRandomnessAndReveal(1, "seed");
        assertEq(gobblers.getGobblerEmissionMultiple(1), 9);

        gobblers.addGoo(500 ether);
        gobblers.mintFromGoo(100 ether, true);
        vm.warp(block.timestamp + 1 days);
        _setRandomnessAndReveal(1, "seed");
        assertEq(gobblers.getGobblerEmissionMultiple(1), 9);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
    // Deposit
    //////////////////////////////////////////////////////////////*/

    // Get reserve balances before they are updated
    // Assess performance fee since last tx
    // Transfer any Goo or Gobblers IN (before minting to prevent ERC777 reentrancy) TODO add test
    // Get reserve balances again
    // Mint fractions to depositor (less management fee)
    // Update reserve balances
    // Emit event

    function testUnitDepositBoth() public {
        // Add Goo and mint Gobblers
        vm.startPrank(users[1]);
        uint256[] memory artGobblers = _addGooAndMintGobblers(500 ether, 2);

        uint256 gooToDeposit = 200 ether;

        // Precondition checks
        // Goo ownership
        uint256 userGooBalance = gobblers.gooBalance(users[1]);
        assertEq(gobblers.gooBalance(address(goober)), 0);
        // Gobbler ownership
        assertEq(gobblers.ownerOf(artGobblers[0]), users[1]);
        assertEq(gobblers.ownerOf(artGobblers[1]), users[1]);
        // Fractions of depositor
        assertEq(goober.balanceOf(users[1]), 0);
        // Total assets and Reserve balances
        (uint256 gooTokens, uint256 gobblerMult) = goober.totalAssets();
        assertEq(gooTokens, 0);
        assertEq(gobblerMult, 0);
        (uint256 gooReserve, uint256 gobblerReserve, uint32 blockTimestampLast) = goober.getReserves();
        assertEq(gooReserve, 0);
        assertEq(gobblerReserve, 0);
        assertEq(blockTimestampLast, 0);

        // Reveal
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(2, "seed");

        // TODO fix event tests
        // Check Deposit event
        // vm.expectEmit(true, true, true, false);
        // emit Deposit(users[1], users[1], artGobblers, gooToDeposit, 0);

        // Check FeesAccrued events
        // vm.expectEmit(true, true, true, false);
        // emit FeesAccrued(FEE_TO, 0, true, 0); // no performance fee assessed
        // vm.expectEmit(true, true, true, false);
        // emit FeesAccrued(FEE_TO, 0, false, 0); // management fee

        // Deposit 2 gobblers and 200 goo
        uint256 fractions = goober.deposit(artGobblers, gooToDeposit, users[1]);
        // Check all the goo tokens were burned
        // Since initial supply = 0, we can just use local vars.
        // TODO(Find a way to call gobblers.gooBalance() for the definition below
        // without stack too deep.
        // uint256 finalSupply =  (300) + gobblers.gooBalance(address(this));
        // TODO(Find a way to call goo.totalSupply for the assert below
        // without stack too deep.
        // assertEq(finalSupply, goo.totalSupply());
        vm.stopPrank();

        // Goo is transferred into vault
        assertEq(gobblers.gooBalance(users[1]), userGooBalance); // no change
        assertEq(gobblers.gooBalance(address(goober)), gooToDeposit);

        // Gobblers are transferred into vault
        assertEq(gobblers.ownerOf(artGobblers[0]), address(goober));
        assertEq(gobblers.ownerOf(artGobblers[1]), address(goober));

        // Fractions are minted to depositor
        assertEq(goober.balanceOf(users[1]), fractions);

        // Reserve balances and total assets are updated
        uint256 expectedGobblerMult = gobblers.getGobblerEmissionMultiple(1) + gobblers.getGobblerEmissionMultiple(2);
        (uint256 gooTokensAfter, uint256 gobblerMultAfter) = goober.totalAssets();
        assertEq(gooTokensAfter, gooToDeposit);
        assertEq(gobblerMultAfter, expectedGobblerMult);
        (uint256 gooReserveAfter, uint256 gobblerReserveAfter, uint32 blockTimestampLastAfter) = goober.getReserves();
        assertEq(gooReserveAfter, gooToDeposit);
        assertEq(gobblerReserveAfter, expectedGobblerMult);
        assertEq(blockTimestampLastAfter, TIME0 + 1 days);
    }

    // Total initial supply of Goo is zero.
    // function testTotalSupply() public {
    // uint256 gooSupply = goo.totalSupply();
    // assertEq(gooSupply, 0);
    // }

    // function testDepositWhenOnlyGoo() public {

    // }

    // function testDepositWhenOnlyGobblers() public {

    // }

    function testUnitRevertFirstDepositOnlyGoo() public {
        vm.startPrank(users[1]);
        uint256[] memory artGobblers = _addGooAndMintGobblers(500 ether, 2);
        assertEq(gobblers.gooBalance(address(goober)), 0);
        assertEq(gobblers.ownerOf(artGobblers[0]), users[1]);
        assertEq(gobblers.ownerOf(artGobblers[1]), users[1]);
        assertEq(goober.balanceOf(users[1]), 0);
        (uint256 gooTokens, uint256 gobblerMult) = goober.totalAssets();
        assertEq(gooTokens, 0);
        assertEq(gobblerMult, 0);
        (uint256 gooReserve, uint256 gobblerReserve, uint32 blockTimestampLast) = goober.getReserves();
        assertEq(gooReserve, 0);
        assertEq(gobblerReserve, 0);
        assertEq(blockTimestampLast, 0);
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(2, "seed");
        vm.expectRevert(abi.encodeWithSelector(IGoober.MustLeaveLiquidity.selector, 0, 17));
        goober.deposit(artGobblers, 0, users[1]);
        vm.stopPrank();
    }

    function testUnitRevertFirstDepositOnlyGobblers() public {
        vm.startPrank(users[1]);
        uint256[] memory artGobblersEmptyArray = new uint256[](0);
        uint256 gooToDeposit = 200 ether;
        assertEq(gobblers.gooBalance(address(goober)), 0);
        assertEq(goober.balanceOf(users[1]), 0);
        (uint256 gooTokens, uint256 gobblerMult) = goober.totalAssets();
        assertEq(gooTokens, 0);
        assertEq(gobblerMult, 0);
        (uint256 gooReserve, uint256 gobblerReserve, uint32 blockTimestampLast) = goober.getReserves();
        assertEq(gooReserve, 0);
        assertEq(gobblerReserve, 0);
        assertEq(blockTimestampLast, 0);
        vm.expectRevert(abi.encodeWithSelector(IGoober.MustLeaveLiquidity.selector, gooToDeposit, 0));
        goober.deposit(artGobblersEmptyArray, gooToDeposit, users[1]);
        vm.stopPrank();
    }

    function testUnitEventDeposit() public {
        // Add Goo and mint Gobblers
        vm.startPrank(users[1]);
        uint256[] memory artGobblers = _addGooAndMintGobblers(500 ether, 2);

        uint256 gooToDeposit = 200 ether;

        // Precondition checks
        // Goo ownership
        gobblers.gooBalance(users[1]);
        assertEq(gobblers.gooBalance(address(goober)), 0);
        // Gobbler ownership
        assertEq(gobblers.ownerOf(artGobblers[0]), users[1]);
        assertEq(gobblers.ownerOf(artGobblers[1]), users[1]);
        // Fractions of depositor
        assertEq(goober.balanceOf(users[1]), 0);
        // Total assets and Reserve balances
        (uint256 gooTokens, uint256 gobblerMult) = goober.totalAssets();
        assertEq(gooTokens, 0);
        assertEq(gobblerMult, 0);
        (uint256 gooReserve, uint256 gobblerReserve, uint32 blockTimestampLast) = goober.getReserves();
        assertEq(gooReserve, 0);
        assertEq(gobblerReserve, 0);
        assertEq(blockTimestampLast, 0);

        // Reveal
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(2, "seed");

        // Check Deposit event
        vm.expectEmit(true, true, false, true, address(goober));
        emit Deposit(users[1], users[1], artGobblers, gooToDeposit, 57143328569039999020);

        // TODO
        // Check FeesAccrued events
        // (uint256 _gooBalance, uint256 _gobblerBalanceMult,) = goober.getReserves();
        // (uint256 fee, uint256 kDebtChange, uint256 deltaK) = goober._previewPerformanceFee(_gooBalance, _gobblerBalanceMult);
        // assertEq(fee,0);
        // assertEq(deltaK,0);
        // vm.expectEmit(true, false, false, true, address(goober));
        // emit FeesAccrued(FEE_TO, 0, true, 0); // no performance fee assessed

        // vm.expectEmit(true, false, false, true, address(goober));
        // emit FeesAccrued(FEE_TO, 57143327590, false, 0); // management fee

        // event FeesAccrued(address indexed feeTo, uint256 fractions, bool performanceFee, uint256 _deltaK);

        // Deposit 2 gobblers and 200 goo
        uint256 fractions = goober.deposit(artGobblers, gooToDeposit, users[1]);
        vm.stopPrank();

        assertEq(fractions, 57143328569039999020);
    }

    function testUnitEventSyncFromDeposit() public {
        // Add Goo and mint Gobblers
        vm.startPrank(users[1]);
        uint256[] memory artGobblers = _addGooAndMintGobblers(500 ether, 2);

        uint256 gooToDeposit = 200 ether;

        // Precondition checks
        // Goo ownership
        gobblers.gooBalance(users[1]);
        assertEq(gobblers.gooBalance(address(goober)), 0);
        // Gobbler ownership
        assertEq(gobblers.ownerOf(artGobblers[0]), users[1]);
        assertEq(gobblers.ownerOf(artGobblers[1]), users[1]);
        // Fractions of depositor
        assertEq(goober.balanceOf(users[1]), 0);
        // Total assets and Reserve balances
        (uint256 gooTokens, uint256 gobblerMult) = goober.totalAssets();
        assertEq(gooTokens, 0);
        assertEq(gobblerMult, 0);
        (uint256 gooReserve, uint256 gobblerReserve, uint32 blockTimestampLast) = goober.getReserves();
        assertEq(gooReserve, 0);
        assertEq(gobblerReserve, 0);
        assertEq(blockTimestampLast, 0);

        // Reveal
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(2, "seed");

        // Check Sync event
        vm.expectEmit(false, false, false, true, address(goober));
        emit Sync(gooToDeposit, 17);

        // Deposit 2 gobblers and 200 goo
        uint256 fractions = goober.deposit(artGobblers, gooToDeposit, users[1]);
        vm.stopPrank();

        assertEq(fractions, 57143328569039999020);
    }

    // function testRevertDepositWhenInsufficientLiquidityMined() public {
    //     // Goober: INSUFFICIENT_LIQUIDITY_MINTED
    // }

    function testUnitSafeDeposit() public {
        // Add Goo and mint Gobblers
        vm.startPrank(users[1]);
        uint256[] memory artGobblers = _addGooAndMintGobblers(500 ether, 2);

        uint256 gooToDeposit = 200 ether;

        // Reveal
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(2, "seed");

        // Deposit 2 gobblers and 200 goo
        uint256 expectedFractions = goober.previewDeposit(artGobblers, gooToDeposit);

        uint256 fractions = goober.safeDeposit(artGobblers, gooToDeposit, users[1], expectedFractions, block.timestamp);
        vm.stopPrank();

        // Fractions minted matches the expected amount
        assertEq(fractions, expectedFractions);
    }

    function testUnitSafeDepositFailsWhenExpired() public {
        // Add Goo and mint Gobblers
        vm.startPrank(users[1]);
        uint256[] memory artGobblers = _addGooAndMintGobblers(500 ether, 2);

        uint256 gooToDeposit = 200 ether;

        // Reveal
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(2, "seed");

        // Deposit 2 gobblers and 200 goo
        uint256 expectedFractions = goober.previewDeposit(artGobblers, gooToDeposit);

        vm.expectRevert(abi.encodeWithSelector(IGoober.Expired.selector, block.timestamp, block.timestamp - 1));

        goober.safeDeposit(artGobblers, gooToDeposit, users[1], expectedFractions, block.timestamp - 1);
    }

    function testUnitSafeDepositFailsWhenInsufficientLiquidityMinted() public {
        // Add Goo and mint Gobblers
        vm.startPrank(users[1]);
        uint256[] memory artGobblers = _addGooAndMintGobblers(500 ether, 2);

        uint256 gooToDeposit = 200 ether;

        // Reveal
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(2, "seed");

        // Deposit 2 gobblers and 200 goo
        uint256 expectedFractions = goober.previewDeposit(artGobblers, gooToDeposit);

        vm.expectRevert(IGoober.MintBelowLimit.selector);

        goober.safeDeposit(artGobblers, gooToDeposit, users[1], expectedFractions + 1, block.timestamp + 1);
    }

    /*//////////////////////////////////////////////////////////////
    // Withdraw
    //////////////////////////////////////////////////////////////*/

    // Get reserves
    // Assess performance fee since last tx
    // Transfer Goo and Gobblers OUT, if any
    // Get reserves again
    // Calculate multiplier
    // Check multipler and Goo both greater than 0
    // Calculate fractions, Check some liquidity will be left over
    // Check approvals, if withdrawing on behalf of someone else
    // Burn fractions from owner
    // Update reserves
    // Emit event

    function testUnitWithdrawBothAll() public {
        // Tests depositing goo and gobbler and withdrawing
        // after 7 days of K growth (increased by a later depositor).

        // User 1 adds gobbler and goo, leaves it in pool.
        vm.startPrank(users[1]);
        uint256[] memory artGobblers1 = new uint256[](1);
        artGobblers1[0] = gobblers.mintFromGoo(100 ether, false);
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(1, "seed");
        uint256 mult1 = gobblers.getGobblerEmissionMultiple(1);
        assertEq(mult1, 9);

        // Check how many fractions we receive.
        uint256 fractions = goober.deposit(artGobblers1, 500 ether, users[1]);
        assertEq(fractions, 65740398537519999020);
        vm.stopPrank();
        // K should be 4500 here, we check.
        (uint256 _GooReserve0, uint256 _GobblerReserve0,) = goober.getReserves();
        uint256 oldK = (_GooReserve0 * _GobblerReserve0);
        assertEq(oldK, 4500 ether);

        // User 2 adds gobbler and goo, tries to withdraw it
        // after time has elapsed (and K has increased).
        vm.startPrank(users[2]);
        uint256[] memory artGobblers2 = new uint256[](1);
        artGobblers2[0] = gobblers.mintFromGoo(100 ether, false);
        vm.warp(TIME0 + 2 days);
        _setRandomnessAndReveal(1, "seed2");
        uint256 mult2 = gobblers.getGobblerEmissionMultiple(2);
        assertEq(mult2, 6);
        goober.deposit(artGobblers2, 500 ether, users[2]);

        // We warp ahead to grow K.
        vm.warp(block.timestamp + 7 days);
        (uint256 _GooReserve1, uint256 _GobblerReserve1,) = goober.getReserves();
        uint256 newK = (_GooReserve1 * _GobblerReserve1);
        assertEq(newK, 32094380310921470254575);

        //(,, uint256 kDelta) = goober._previewPerformanceFee(_GooReserve1, _GobblerReserve1);
        // kDelta is 414531353282231156 here (we make the above function public to calc)
        uint256 kDelta = 414531353282231156;
        vm.stopPrank();

        // Check to see user 1 can withdraw as much as they can.
        // K has grown from 4500 ether to ~ 32094 ether, around 7132%.
        vm.startPrank(users[1]);
        vm.expectEmit(true, false, false, true);
        // The summed 'fractions' that FeesAccrued emits minus fes are
        // equal to how many fractions total have been accrued by the user.
        emit FeesAccrued(FEE_TO, 4952963198578904942, true, kDelta);
        // TODO(Calc how much are lost to fees below with the 30bps)
        uint256 fractionsNew = goober.withdraw(artGobblers1, 500 ether, users[1], users[1]);
        // We withdrew everything we put in, and still own 10197914272 shares,
        // in other words we grew our position by 10197914272 shares.
        assertEq(fractionsNew, 55542484114047516323);
        uint256 fractionsLeft = goober.balanceOf(users[1]);
        assertEq(fractionsLeft, fractions - fractionsNew);
        // We have 10197914272 shares left.
        assertEq(fractionsLeft, 10197914423472482697);

        vm.stopPrank();
    }

    // function testWithdrawWhenDepositedOnlyGoo() public {}

    // function testWithdrawWhenDepositedOnlyGobblers() public {}

    function testUnitRevertWithdrawWhenOwnerIsNotReceiver() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);
        uint256[] memory artGobblers = new uint256[](1);
        artGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        vm.stopPrank();

        vm.startPrank(users[2]);
        gobblers.addGoo(500 ether);
        uint256[] memory artGobblers2 = new uint256[](1);
        artGobblers2[0] = gobblers.mintFromGoo(100 ether, true);
        vm.stopPrank();

        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(2, "seed");

        vm.prank(users[1]);
        goober.deposit(artGobblers, 200 ether, users[1]);

        vm.startPrank(users[2]);
        uint256 fractions = goober.deposit(artGobblers2, 200 ether, users[2]);
        goober.approve(OTHER, 1); // not the right amount
        vm.stopPrank();

        vm.warp(block.timestamp + 7 days);

        vm.expectRevert(IGoober.InsufficientAllowance.selector);

        vm.prank(OTHER);
        goober.withdraw(artGobblers2, fractions, users[2], users[2]);
    }

    function testUnitWithdrawWhenOwnerIsNotReceiverButWithSufficientAllowance() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);
        uint256[] memory artGobblers = new uint256[](1);
        artGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        vm.stopPrank();

        vm.startPrank(users[2]);
        gobblers.addGoo(500 ether);
        uint256[] memory artGobblers2 = new uint256[](1);
        artGobblers2[0] = gobblers.mintFromGoo(100 ether, true);
        vm.stopPrank();

        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(2, "seed");

        vm.prank(users[1]);
        goober.deposit(artGobblers, 200 ether, users[1]);

        vm.startPrank(users[2]);
        uint256 fractions = goober.deposit(artGobblers2, 200 ether, users[2]);
        goober.approve(OTHER, type(uint256).max);
        vm.stopPrank();

        vm.warp(block.timestamp + 7 days);

        // Other account with sufficient allowance can withdraw

        vm.prank(OTHER);
        goober.withdraw(artGobblers2, fractions, users[2], users[2]);
    }

    function testUnitWithdrawWhenOwnerIsNotReceiverButWithSufficientAllowanceThatIsNotMax() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);
        uint256[] memory artGobblers = new uint256[](1);
        artGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        vm.stopPrank();

        vm.startPrank(users[2]);
        gobblers.addGoo(500 ether);
        uint256[] memory artGobblers2 = new uint256[](1);
        artGobblers2[0] = gobblers.mintFromGoo(100 ether, true);
        vm.stopPrank();

        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(2, "seed");

        vm.prank(users[1]);
        goober.deposit(artGobblers, 200 ether, users[1]);

        vm.startPrank(users[2]);
        uint256 fractions = goober.deposit(artGobblers2, 200 ether, users[2]);
        goober.approve(OTHER, type(uint256).max - 1);
        vm.stopPrank();

        vm.warp(block.timestamp + 7 days);

        // Other account with sufficient allowance can withdraw

        vm.prank(OTHER);
        goober.withdraw(artGobblers2, fractions, users[2], users[2]);
    }

    // test withdraw when owner != receiver

    function testUnitEventWithdraw() public {
        // Add Goo and mint Gobblers
        vm.startPrank(users[1]);
        uint256[] memory artGobblers = _addGooAndMintGobblers(500 ether, 2);
        uint256[] memory artGobblersToWithdraw = new uint256[](1);

        artGobblersToWithdraw[0] = artGobblers[0];

        uint256 gooToDeposit = 200 ether;

        // Reveal
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(2, "seed");

        // Deposit 2 gobblers and 200 goo
        uint256 expectedFractionsOut = goober.previewDeposit(artGobblers, gooToDeposit);

        goober.safeDeposit(artGobblers, gooToDeposit, users[1], expectedFractionsOut, block.timestamp + 1);

        vm.warp(block.timestamp + 7 days);

        uint256 userGooBefore = goo.balanceOf(users[1]);
        uint256 gooToWithdraw = 10 ether;

        uint256 expectedFractionsIn = goober.previewWithdraw(artGobblersToWithdraw, gooToWithdraw);

        assertEq(goober.balanceOf(users[1]), expectedFractionsOut);

        vm.expectEmit(true, true, true, true, address(goober));
        emit Withdraw(users[1], users[1], users[1], artGobblersToWithdraw, gooToWithdraw, expectedFractionsIn);

        uint256 fractionsIn = goober.safeWithdraw(
            artGobblersToWithdraw, gooToWithdraw, users[1], users[1], expectedFractionsIn, block.timestamp + 1
        );

        assertEq(fractionsIn, expectedFractionsIn);

        uint256 userGooAfter = goo.balanceOf(users[1]);

        // The users GOO balance should have changed by the same amount as gooToWithdraw.
        assertEq(userGooAfter - userGooBefore, gooToWithdraw);

        // The owner of the Gobbler should now be the user again.
        assertEq(gobblers.ownerOf(artGobblersToWithdraw[0]), users[1]);
        vm.stopPrank();
    }

    // Goober: INSUFFICIENT LIQUIDITY WITHDRAW edge cases

    // TODO getting std Arithmetic over/underflow revert before Goober revert
    // function testRevertDepositWhenGooBalanceWouldOverflowuint256() public {
    //     _writeTokenBalance(users[10], address(goo), type(uint128).max);

    //     vm.startPrank(users[10]);
    //     uint256[] memory artGobblers = _addGooAndMintGobblers(500 ether, 1);

    //     vm.warp(TIME0 + 1 days);
    //     _setRandomnessAndReveal(1, "seed");

    //     vm.expectRevert("Goober: OVERFLOW");

    //     goober.deposit(artGobblers, type(uint256).max + 1, users[10]);
    // }

    function testUnitRevertWithdrawWhenInsufficientGobblerMult() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);
        uint256[] memory artGobblers = new uint256[](2);
        uint256[] memory artGobblersHold = new uint256[](1);

        artGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        artGobblers[1] = gobblers.mintFromGoo(100 ether, true);
        artGobblersHold[0] = gobblers.mintFromGoo(100 ether, true);

        vm.warp(block.timestamp + 1 days);

        _setRandomnessAndReveal(3, "seed");

        goober.deposit(artGobblers, 500 ether, users[1]);

        vm.expectRevert(abi.encodeWithSelector(IGoober.MustLeaveLiquidity.selector, 0, 17));

        goober.withdraw(new uint256[](0), 500 ether, users[1], users[1]);
    }

    // function testRevertWithdrawWhenWithdrawingLastGoo() public {

    // }

    function testUnitRevertWithdrawWhenWithdrawingLastGobbler() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);
        uint256[] memory artGobblers = new uint256[](2);
        uint256[] memory artGobblersHold = new uint256[](1);

        artGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        artGobblers[1] = gobblers.mintFromGoo(100 ether, true);
        artGobblersHold[0] = gobblers.mintFromGoo(100 ether, true);

        vm.warp(block.timestamp + 1 days);

        _setRandomnessAndReveal(3, "seed");

        goober.deposit(artGobblers, 500 ether, users[1]);

        vm.expectRevert(abi.encodeWithSelector(IGoober.MustLeaveLiquidity.selector, 490 ether, 0));

        goober.withdraw(artGobblers, 10 ether, users[1], users[1]);
    }

    function testUnitWithdraw() public {
        // Add Goo and mint Gobblers
        vm.startPrank(users[1]);
        uint256[] memory artGobblers = _addGooAndMintGobblers(500 ether, 2);
        uint256[] memory artGobblersToWithdraw = new uint256[](1);

        artGobblersToWithdraw[0] = artGobblers[0];

        uint256 gooToDeposit = 200 ether;

        // Reveal
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(2, "seed");

        // Deposit 2 gobblers and 200 goo
        uint256 expectedFractionsOut = goober.previewDeposit(artGobblers, gooToDeposit);

        goober.safeDeposit(artGobblers, gooToDeposit, users[1], expectedFractionsOut, block.timestamp + 1);

        vm.warp(block.timestamp + 7 days);

        uint256 userGooBefore = goo.balanceOf(users[1]);
        uint256 gooToWithdraw = 10 ether;

        uint256 expectedFractionsIn = goober.previewWithdraw(artGobblersToWithdraw, gooToWithdraw);

        uint256 fractionsIn = goober.safeWithdraw(
            artGobblersToWithdraw, gooToWithdraw, users[1], users[1], expectedFractionsIn, block.timestamp + 1
        );

        assertEq(fractionsIn, expectedFractionsIn);

        uint256 userGooAfter = goo.balanceOf(users[1]);

        // The users GOO balance should have changed by the same amount as gooToWithdraw.
        assertEq(userGooAfter - userGooBefore, gooToWithdraw);

        // The owner of the Gobbler should now be the user again.
        assertEq(gobblers.ownerOf(artGobblersToWithdraw[0]), users[1]);

        vm.stopPrank();
    }

    function testUnitWithdrawRevertsWhenExpired() public {
        // Add Goo and mint Gobblers
        vm.startPrank(users[1]);
        uint256[] memory artGobblers = _addGooAndMintGobblers(500 ether, 2);
        uint256[] memory artGobblersToWithdraw = new uint256[](1);

        artGobblersToWithdraw[0] = artGobblers[0];

        uint256 gooToDeposit = 200 ether;

        // Reveal
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(2, "seed");

        // Deposit 2 gobblers and 200 goo
        uint256 expectedFractionsOut = goober.previewDeposit(artGobblers, gooToDeposit);

        goober.safeDeposit(artGobblers, gooToDeposit, users[1], expectedFractionsOut, block.timestamp + 1);

        vm.warp(block.timestamp + 7 days);

        uint256 gooToWithdraw = 10 ether;

        uint256 expectedFractionsIn = goober.previewWithdraw(artGobblersToWithdraw, gooToWithdraw);

        vm.expectRevert(abi.encodeWithSelector(IGoober.Expired.selector, block.timestamp, block.timestamp - 1));

        goober.safeWithdraw(
            artGobblersToWithdraw, gooToWithdraw, users[1], users[1], expectedFractionsIn, block.timestamp - 1
        );
    }

    function testUnitWithdrawRevertsWhenFractionsBurnedExceedsLimit() public {
        // Add Goo and mint Gobblers
        vm.startPrank(users[1]);
        uint256[] memory artGobblers = _addGooAndMintGobblers(500 ether, 2);
        uint256[] memory artGobblersToWithdraw = new uint256[](1);

        artGobblersToWithdraw[0] = artGobblers[0];

        uint256 gooToDeposit = 200 ether;

        // Reveal
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(2, "seed");

        // Deposit 2 gobblers and 200 goo
        uint256 expectedFractionsOut = goober.previewDeposit(artGobblers, gooToDeposit);

        goober.safeDeposit(artGobblers, gooToDeposit, users[1], expectedFractionsOut, block.timestamp + 1);

        vm.warp(block.timestamp + 7 days);

        uint256 gooToWithdraw = 10 ether;

        uint256 expectedFractionsIn = goober.previewWithdraw(artGobblersToWithdraw, gooToWithdraw);

        vm.expectRevert(IGoober.BurnAboveLimit.selector);

        goober.safeWithdraw(
            artGobblersToWithdraw, gooToWithdraw, users[1], users[1], expectedFractionsIn - 1, block.timestamp + 1
        );
    }

    // Goober: INSUFFICIENT_ALLOWANCE

    /*//////////////////////////////////////////////////////////////
    // Swap
    //////////////////////////////////////////////////////////////*/

    // Check at least some Goo or Gobblers are being swapped out
    // Get reserves
    // Check receiver address is not Goo nor Gobbler
    // Transfer any Goo or Gobblers to correct out addresses
    // If flash loan, call flash loan
    // Transfer any Goo or Gobblers IN
    // Get reserves again
    // Calculate amounts in — did we get more in than we got out? good, otherwise bad
    // Check at least some Goo or Gobblers are being swapped in
    // Check growth of k
    // Assess performance fee on growth of k
    // Update reserves
    // Emit event

    function testUnitSwap() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);

        uint256[] memory artGobblers = new uint256[](2);
        uint256[] memory artGobblersTwo = new uint256[](1);
        uint256[] memory artGobblersThree = new uint256[](1);
        artGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        artGobblers[1] = gobblers.mintFromGoo(100 ether, true);
        artGobblersTwo[0] = gobblers.mintFromGoo(100 ether, true);
        artGobblersThree[0] = artGobblers[0];

        vm.warp(block.timestamp + 1 days);

        _setRandomnessAndReveal(3, "seed");

        uint256 gooTokens = 200 ether;
        uint256 fractions = goober.deposit(artGobblers, gooTokens, users[1]);

        // TODO

        bytes memory data;

        goober.swap(artGobblersTwo, 100 ether, artGobblersThree, 0 ether, users[1], data);

        fractions = goober.withdraw(artGobblersTwo, 100 ether, users[1], users[1]);

        // TODO assertions
    }

    function testUnitSwapEvent() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);

        uint256[] memory artGobblers = new uint256[](2);
        uint256[] memory artGobblersTwo = new uint256[](1);
        uint256[] memory artGobblersThree = new uint256[](1);
        artGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        artGobblers[1] = gobblers.mintFromGoo(100 ether, true);
        artGobblersTwo[0] = gobblers.mintFromGoo(100 ether, true);
        artGobblersThree[0] = artGobblers[0];

        vm.warp(block.timestamp + 1 days);

        _setRandomnessAndReveal(3, "seed");

        uint256 gooTokens = 200 ether;
        uint256 fractions = goober.deposit(artGobblers, gooTokens, users[1]);

        bytes memory data;

        // Check Swap event
        vm.expectEmit(true, true, false, true, address(goober));
        emit Swap(users[1], users[1], 100 ether, 6, 0, 9);

        goober.swap(artGobblersTwo, 100 ether, artGobblersThree, 0 ether, users[1], data);
    }

    // Goober: INSUFFICIENT_OUTPUT_AMOUNT

    // Goober: INVALID_TO

    // Goober: INSUFFICIENT_INPUT_AMOUNT

    function testUnitSafeSwap() public {
        vm.startPrank(users[1]);
        uint256[] memory artGobblers = _addGooAndMintGobblers(500 ether, 4);

        uint256[] memory artGobblersToDeposit = new uint256[](3);
        artGobblersToDeposit[0] = artGobblers[0];
        artGobblersToDeposit[1] = artGobblers[1];
        artGobblersToDeposit[2] = artGobblers[2];

        uint256[] memory artGobblersToSwap = new uint256[](1);
        artGobblersToSwap[0] = artGobblers[3];

        uint256[] memory artGobblersOut = new uint256[](1);
        artGobblersOut[0] = artGobblers[0];

        uint256 gooToDeposit = 200 ether;

        // Reveal
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(4, "seed");

        // Deposit 2 gobblers and 200 goo
        uint256 expectedFractions = goober.previewDeposit(artGobblersToDeposit, gooToDeposit);

        goober.safeDeposit(artGobblersToDeposit, gooToDeposit, users[1], expectedFractions, block.timestamp);

        bytes memory data;

        int256 expectedErroneousGoo = goober.previewSwap(artGobblersToSwap, 235765844523515264, artGobblersOut, 0);

        int256 erroneousGoo = goober.safeSwap(
            0, block.timestamp + 1, artGobblersToSwap, 235765844523515264, artGobblersOut, 0, users[1], data
        );

        assertEq(expectedErroneousGoo, erroneousGoo);

        vm.stopPrank();
    }

    function testUnitSafeSwapRevertsWhenExpired() public {
        vm.startPrank(users[1]);
        uint256[] memory artGobblers = _addGooAndMintGobblers(500 ether, 4);

        uint256[] memory artGobblersToDeposit = new uint256[](3);
        artGobblersToDeposit[0] = artGobblers[0];
        artGobblersToDeposit[1] = artGobblers[1];
        artGobblersToDeposit[2] = artGobblers[2];

        uint256[] memory artGobblersToSwap = new uint256[](1);
        artGobblersToSwap[0] = artGobblers[3];

        uint256[] memory artGobblersOut = new uint256[](1);
        artGobblersOut[0] = artGobblers[0];

        uint256 gooToDeposit = 200 ether;

        // Reveal
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(4, "seed");

        // Deposit 2 gobblers and 200 goo
        uint256 expectedFractions = goober.previewDeposit(artGobblersToDeposit, gooToDeposit);

        goober.safeDeposit(artGobblersToDeposit, gooToDeposit, users[1], expectedFractions, block.timestamp);

        bytes memory data;

        vm.expectRevert(abi.encodeWithSelector(IGoober.Expired.selector, block.timestamp, block.timestamp - 1));

        goober.safeSwap(
            0, block.timestamp - 1, artGobblersToSwap, 235765844523515264, artGobblersOut, 0, users[1], data
        );
    }

    function testUnitSafeSwapRevertsWhenErroneousGooIsTooLarge() public {
        // A user sets up the vault
        vm.startPrank(users[3]);
        uint256[] memory artGobblers = _addGooAndMintGobblers(500 ether, 4);

        uint256[] memory artGobblersToDeposit = new uint256[](3);
        artGobblersToDeposit[0] = artGobblers[0];
        artGobblersToDeposit[1] = artGobblers[1];
        artGobblersToDeposit[2] = artGobblers[2];

        // Reveal
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(4, "seed");

        uint256 gooToDeposit = 300 ether;

        // Deposit 3 gobblers and 300 goo
        uint256 expectedFractions = goober.previewDeposit(artGobblersToDeposit, gooToDeposit);

        goober.safeDeposit(artGobblersToDeposit, gooToDeposit, users[1], expectedFractions, block.timestamp);

        // Then sends a gobbler to a friend

        gobblers.transferFrom(users[3], users[1], artGobblers[3]);

        vm.stopPrank();

        uint256[] memory noGobblers = new uint256[](0);

        // That friend decides they want goo.
        vm.startPrank(users[1]);

        uint256[] memory artGobblersToSwap = new uint256[](1);
        artGobblersToSwap[0] = artGobblers[3];

        uint256[] memory artGobblersOut = new uint256[](1);
        artGobblersOut[0] = artGobblers[0];

        uint256 swapPreview = uint256(-goober.previewSwap(artGobblersToSwap, 0, noGobblers, 0));
        vm.stopPrank();

        // As they are about to sell the gobbler, somebody frontruns them and buys a gobbler
        vm.startPrank(users[2]);

        uint256[] memory artGobblersOutTwo = new uint256[](1);
        artGobblersOutTwo[0] = artGobblers[1];

        goober.swap(
            noGobblers,
            uint256(goober.previewSwap(noGobblers, 1, artGobblersOutTwo, 0)) + 1,
            artGobblersOutTwo,
            0,
            users[2],
            ""
        );

        vm.stopPrank();

        // But, they used safeSwap, so they don't loose money.
        vm.startPrank(users[1]);

        // This tests the case of too much goo out
        // TODO(Think, is this something safe swap should prevent? Or only too much goo in?)
        vm.expectRevert(abi.encodeWithSelector(IGoober.ExcessiveErroneousGoo.selector, 88163488180920139792, 1));
        goober.safeSwap(1, block.timestamp + 1, artGobblersToSwap, 0, noGobblers, swapPreview, users[1], "");

        // So the user decides to make a trade anyway at this better price
        swapPreview = uint256(-goober.previewSwap(artGobblersToSwap, 0, noGobblers, 0));
        vm.stopPrank();

        // But that pesky frontrunner decides to sell back the gobbler, he didn't like it
        vm.startPrank(users[2]);
        goober.swap(
            artGobblersOutTwo,
            0,
            noGobblers,
            uint256(-goober.previewSwap(artGobblersOutTwo, 0, noGobblers, 0)),
            users[2],
            ""
        );
        vm.stopPrank();

        // Our slower trader is still protected though, because they are using safeSwap
        vm.startPrank(users[1]);
        vm.expectRevert(abi.encodeWithSelector(IGoober.ExcessiveErroneousGoo.selector, 88252089333012275015, 1));
        goober.safeSwap(1, block.timestamp + 1, artGobblersToSwap, 0, noGobblers, swapPreview, users[1], "");
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
    // Accounting
    //////////////////////////////////////////////////////////////*/

    function testUnitTotalAssets() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);
        uint256[] memory artGobblers = new uint256[](1);
        uint256[] memory artGobblersTwo = new uint256[](1);
        uint256[] memory artGobblersThree = new uint256[](1);
        artGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        artGobblersTwo[0] = gobblers.mintFromGoo(100 ether, true);
        artGobblersThree[0] = gobblers.mintFromGoo(100 ether, true);

        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(3, "seed");

        uint256 expectedGooTokens = 300 ether;
        uint256 expectedGobblerMult = gobblers.getUserEmissionMultiple(users[1]);

        goober.deposit(artGobblers, 100 ether, users[1]);
        goober.deposit(artGobblersTwo, 100 ether, users[1]);
        goober.deposit(artGobblersThree, 100 ether, users[1]);

        (uint256 actualGooTokens, uint256 actualGobblerMult) = goober.totalAssets();
        assertEq(actualGooTokens, expectedGooTokens);
        assertEq(actualGobblerMult, expectedGobblerMult);
    }

    function testUnitGetReserves() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);
        uint256[] memory artGobblers = new uint256[](1);
        artGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(1, "seed");
        uint256 expectedGooTokens = 100 ether;
        uint256 expectedGobblerMult = gobblers.getUserEmissionMultiple(users[1]);
        goober.deposit(artGobblers, expectedGooTokens, users[1]);
        (uint256 gooReserves, uint256 gobblerReserves, uint32 lastBlockTimestamp) = goober.getReserves();
        assertEq(gooReserves, expectedGooTokens);
        assertEq(gobblerReserves, expectedGobblerMult);
        assertEq(uint256(lastBlockTimestamp), block.timestamp);
    }

    function testUnitConvertToFractions() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);
        uint256[] memory artGobblers = new uint256[](1);
        uint256[] memory artGobblersTwo = new uint256[](1);
        artGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        artGobblersTwo[0] = gobblers.mintFromGoo(100 ether, true);

        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(2, "seed");
        uint256 noSlippageFractions = goober.convertToFractions(100, 100);
        assertEq(noSlippageFractions, 100);
        goober.deposit(artGobblers, 100 ether, users[1]);
        noSlippageFractions = goober.convertToFractions(8, 99999996666666669999);
        assertEq(noSlippageFractions, 28284270775999999037);
    }

    function testUnitConvertToAssets() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);
        uint256[] memory artGobblers = new uint256[](1);
        artGobblers[0] = gobblers.mintFromGoo(100 ether, true);

        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(1, "seed");
        (uint256 gooToken, uint256 gobblerMult) = goober.convertToAssets(100);
        assertEq(gooToken, 0);
        assertEq(gobblerMult, 0);
        goober.deposit(artGobblers, 100 ether, users[1]);
        (gooToken, gobblerMult) = goober.convertToAssets(29999999000 * 1e9);
        // Because management fee
        assertEq(gooToken, 99999996666666669999);
        // Because management fee
        assertEq(gobblerMult, 8);
    }

    function testUnitPreviewDeposit() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);
        // Test first deposit
        uint256[] memory artGobblers = new uint256[](1);
        artGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(1, "seed");
        uint256 expected = goober.previewDeposit(artGobblers, 100 ether);
        uint256 actual = goober.deposit(artGobblers, 100 ether, users[1]);
        assertEq(expected, actual);
        // Test second deposit
        uint256[] memory artGobblersTwo = new uint256[](1);
        artGobblersTwo[0] = gobblers.mintFromGoo(100 ether, true);
        vm.warp(block.timestamp + 1 days);
        _setRandomnessAndReveal(1, "seed");
        expected = goober.previewDeposit(artGobblersTwo, 100 ether);
        actual = goober.deposit(artGobblersTwo, 100 ether, users[1]);
        assertEq(expected, actual);
    }

    function testUnitPreviewWithdraw() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);
        uint256[] memory artGobblers = new uint256[](1);
        uint256[] memory artGobblersTwo = new uint256[](1);
        uint256[] memory artGobblersThree = new uint256[](1);
        artGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        artGobblersTwo[0] = gobblers.mintFromGoo(100 ether, true);
        artGobblersThree[0] = gobblers.mintFromGoo(100 ether, true);
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(3, "seed");
        goober.deposit(artGobblers, 100 ether, users[1]);
        goober.deposit(artGobblersTwo, 100 ether, users[1]);
        goober.deposit(artGobblersThree, 100 ether, users[1]);
        uint256 expected = goober.previewWithdraw(artGobblersThree, 100 ether);
        uint256 actual = goober.withdraw(artGobblersThree, 100 ether, users[1], users[1]);
        expected = goober.previewWithdraw(artGobblersTwo, 100 ether);
        actual = goober.withdraw(artGobblersTwo, 100 ether, users[1], users[1]);
        uint256[] memory artGobblersFour = new uint256[](1);
        artGobblersFour[0] = gobblers.mintFromGoo(100 ether, true);
        vm.expectRevert(IGoober.InvalidNFT.selector);
        goober.previewWithdraw(artGobblersFour, 100 ether);
        assertEq(expected, actual);
    }

    function testUnitPreviewSwapExactGobbler() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);
        uint256[] memory gobblersOut = new uint256[](1);
        gobblersOut[0] = gobblers.mintFromGoo(100 ether, true);

        vm.warp(block.timestamp + 1 days);
        _setRandomnessAndReveal(1, "1");

        gobblers.addGoo(500 ether);
        uint256[] memory gobblersIn = new uint256[](1);
        gobblersIn[0] = gobblers.mintFromGoo(100 ether, true);

        vm.warp(block.timestamp + 1 days);
        _setRandomnessAndReveal(1, "1");

        goober.deposit(gobblersOut, 100 ether, users[1]);

        uint256 gooIn = 301808132521938937;
        uint256 gooOut = 0 ether;

        int256 expectedAdditionalGooRequired = 301808132521938937;
        int256 previewAdditionalGooRequired = goober.previewSwap(gobblersIn, 0, gobblersOut, gooOut);
        assertEq(previewAdditionalGooRequired, expectedAdditionalGooRequired);
        assertEq(goober.previewSwap(gobblersIn, gooIn, gobblersOut, gooOut), 0);
        bytes memory data;
        int256 erroneousGoo = goober.swap(gobblersIn, gooIn, gobblersOut, gooOut, users[1], data);
        assertEq(erroneousGoo, int256(0));
        uint256[] memory gobblersInNew = new uint256[](1);
        gobblersInNew[0] = gobblers.mintFromGoo(100 ether, true);
        vm.expectRevert(IGoober.InvalidNFT.selector);
        goober.previewSwap(gobblersInNew, 0, gobblersOut, gooOut);
        vm.stopPrank();
    }

    function testUnitPreviewSwapExactGoo() public {
        vm.startPrank(users[1]);
        uint256[] memory gobblersOut = new uint256[](1);
        gobblersOut[0] = gobblers.mintFromGoo(100 ether, false);
        uint256[] memory gobblersZero = new uint256[](0);

        vm.warp(block.timestamp + 1 days);
        _setRandomnessAndReveal(1, "1");

        goober.deposit(gobblersOut, 100 ether, users[1]);

        // Fee = 150451354062186560 based on erroneous goo calc for 100 ether in the pool
        // and a swap of 50 ether.
        // TODO(Express how to do that calc here based on other vars)
        uint256 feeExpected = 150451354062186560;
        uint256 gooOut = 50 ether;
        uint256 gooIn = gooOut + feeExpected;
        assertEq(goober.previewSwap(gobblersZero, gooIn, gobblersZero, gooOut), 0);

        // Check we can swap.
        int256 erroneousGoo = goober.swap(gobblersZero, gooIn, gobblersZero, gooOut, users[1], "");
        assertEq(erroneousGoo, int256(0));

        // Check we got received the fee from the banal goo swap.
        (uint256 _GooReserve,,) = goober.getReserves();
        assertEq(_GooReserve, (100 ether + (gooIn - gooOut)));

        vm.stopPrank();
    }

    function testUnitPreviewSwapFail() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);
        uint256[] memory gobblersOut = new uint256[](1);
        gobblersOut[0] = gobblers.mintFromGoo(100 ether, true);

        vm.warp(block.timestamp + 1 days);
        _setRandomnessAndReveal(1, "1");

        gobblers.addGoo(500 ether);
        uint256[] memory gobblersIn = new uint256[](1);
        gobblersIn[0] = gobblers.mintFromGoo(100 ether, true);

        vm.warp(block.timestamp + 1 days);
        _setRandomnessAndReveal(1, "1");

        goober.deposit(gobblersOut, 100 ether, users[1]);

        uint256 gooIn = 301808132521938937;
        uint256 gooOut = 0 ether;

        int256 expectedAdditionalGooRequired = 301808132521938937;
        int256 previewAdditionalGooRequired = goober.previewSwap(gobblersIn, 0, gobblersOut, gooOut);
        assertEq(previewAdditionalGooRequired, expectedAdditionalGooRequired);
        assertEq(goober.previewSwap(gobblersIn, gooIn, gobblersOut, gooOut), 0);
        bytes memory data;
        vm.expectRevert(
            abi.encodeWithSelector(
                IGoober.InsufficientGoo.selector, 1, 699999999999999999998840968, 700000000000000000000000000
            )
        );
        goober.swap(gobblersIn, gooIn - 1, gobblersOut, gooOut, users[1], data);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
    // Mint Gobbler
    //////////////////////////////////////////////////////////////*/

    function testUnitMint() public {
        // Safety check to verify starting gobblerPrice is correct.
        assertEq(gobblers.gobblerPrice(), 73013654753028651285);

        // Mint the first gobbler
        vm.startPrank(users[10]);
        uint256[] memory artGobbler = new uint256[](1);
        artGobbler[0] = gobblers.mintFromGoo(75 ether, false);
        // Check to see we own the first Gobbler.
        assertEq(gobblers.ownerOf(1), users[10]);
        // Warp a day ahead until we can reveal Gobbler 1.
        vm.warp(block.timestamp + 86400);
        _setRandomnessAndReveal(1, "seed");
        uint256 gobblerMult = (gobblers.getGobblerEmissionMultiple(artGobbler[0]));
        // Based on our seed, we get a mult of 9 here.
        assertEq(gobblerMult, 9);

        // Pool is setup by depositing 1 gobbler and 81 goo.
        // We do this after warp to not accrue extra goo.
        // Depositing automatically makes the goo virtual.
        uint256 gooTokens = 81 ether;
        goober.deposit(artGobbler, gooTokens, users[10]);
        vm.stopPrank();

        // Safety check to verify new mint price after warp and mint.
        assertEq(gobblers.gobblerPrice(), 52987405899699731484);

        // Now we have pool virtual goo = 81 and pool mult = 9.
        // The goo/mult of our pool is <= goo/mult of the auction,
        // since: 81 / 9 = 9 >= 52.987 / 7.3294 ~= 7.
        // We also have enough goo to mint a single gobbler.
        // NOTE(Getting both of the above to be true is a very delicate
        // balance, especially tricky if you want to test minting
        // more than 1 gobbler here.)

        // Mint a gobbler, and check emitted event matches.
        // NOTE(Updates K, reserves and VRGDA in the process)
        vm.prank(MINTER);
        goober.mintGobbler();

        // Check our Goo balance went down from minting: 81 - 52.99 ~= 28.01.
        (uint256 _GooReserve,,) = goober.getReserves();
        assertEq(_GooReserve, 28012594100300268516);

        // Warp ahead to reveal second gobbler.
        vm.warp(block.timestamp + 1 days);
        // Changing the seed string changes the randomness, and thus the rolled mult.
        _setRandomnessAndReveal(1, "seed2");
        // Check we own the second minted gobbler.
        assertEq(gobblers.ownerOf(2), address(goober));
        (uint256 _newGooReserve, uint256 _newGobblerReserve,) = goober.getReserves();
        // Check we have 15 total mult including the previous 9, since we minted a 6.
        assertEq(_newGobblerReserve, 15);
        // Check our goo balance updated from emission.
        assertEq(_newGooReserve, 46140671657193055549);
    }

    function testUnitMintMultiple() public {
        // Mints exactly 3 gobblers in a single mintGobblers() call.
        // NOTE Each mint will update auction price,
        // goo balance and mult balance (after 24hr);
        // Safety check to verify starting gobblerPrice is correct.
        assertEq(gobblers.gobblerPrice(), 73013654753028651285);

        // Add enough Goo to vault to be able mint three Gobblers.
        // we calculate the needed go by summing the incremental VRGDA
        // price of 3 incremental mints, after an initial mint and 24
        // hours to setup the pool.
        // Needed goo is exactly 175995503714107834819 (around 175.95 goo);

        // Mint the first gobbler to setup the pool.
        vm.startPrank(users[10]);
        uint256[] memory artGobbler = new uint256[](1);
        artGobbler[0] = gobblers.mintFromGoo(75 ether, false);

        vm.warp(block.timestamp + 86400);
        _setRandomnessAndReveal(1, "seed");
        uint256 gobblerMult = (gobblers.getGobblerEmissionMultiple(artGobbler[0]));
        // Based on our seed, we get a mult of 9 here.
        assertEq(gobblerMult, 9);

        // To get the amount (sum) to predict gooSpent:
        // NOTE commented out as it would bump the auction price)
        // uint256[] memory artGobblers = new uint256[](2);
        // artGobblers[0] = gobblers.mintFromGoo(100 ether, false);
        // uint256 mintPrice2 = uint256(gobblers.gobblerPrice());
        // assertEq(mintPrice2, 55730397425599282914);
        // artGobblers[1] = gobblers.mintFromGoo(120 ether, false);
        // uint256 mintPrice3 = uint256(gobblers.gobblerPrice());
        // assertEq(mintPrice3, 58615385439085817001);
        // uint256 sum = 52987405899699731484 + mintPrice2 + mintPrice3;
        // assertEq(sum, 167333188764384831399);

        // NOTE dilemma: since we added a gobbler to setup the pool,
        // We need extra goo to increase the numerator of our goo/gobbler
        // to satisfy the > auction goo/gobbler condition.
        // However, if we add too much more goo, we will mint another gobbler,
        // thus increasing the denomenator.
        // This makes testing for a VaultMint with *true* BalanceTerminated
        // inherently difficult, so we expect a false here.

        uint256 gooTokens = 200 ether;
        goober.deposit(artGobbler, gooTokens, users[10]);
        vm.stopPrank();

        // Should mint 3
        vm.prank(MINTER);
        goober.mintGobbler();

        // Check to see the pool owns Gobbler id 2, 3 and 4.
        assertEq(gobblers.ownerOf(2), address(goober));
        assertEq(gobblers.ownerOf(3), address(goober));
        assertEq(gobblers.ownerOf(4), address(goober));
    }

    function testUnitCantUnrevealedCantEscapeVault() public {
        vm.startPrank(users[1]);
        uint256[] memory artGobbler = new uint256[](1);
        artGobbler[0] = gobblers.mintFromGoo(100 ether, false);
        // Warp a day ahead until we can reveal Gobbler 1.
        vm.warp(block.timestamp + 86400);
        _setRandomnessAndReveal(1, "seed");
        goober.deposit(artGobbler, 100 ether, users[1]);
        // Let's make sure we can't withdraw or swap the unrevealed gobbler
        uint256[] memory artGobblerUnrevealed = new uint256[](1);
        artGobblerUnrevealed[0] = gobblers.mintFromGoo(100 ether, false);
        gobblers.transferFrom(users[1], address(goober), artGobblerUnrevealed[0]);
        vm.expectRevert(abi.encodeWithSelector(IGoober.InvalidMultiplier.selector, artGobblerUnrevealed[0]));
        goober.previewWithdraw(artGobblerUnrevealed, 0);

        vm.expectRevert(abi.encodeWithSelector(IGoober.InvalidMultiplier.selector, artGobblerUnrevealed[0]));
        goober.withdraw(artGobblerUnrevealed, 0, users[1], users[1]);

        vm.expectRevert(abi.encodeWithSelector(IGoober.InvalidMultiplier.selector, artGobblerUnrevealed[0]));
        goober.previewSwap(artGobblerUnrevealed, 0, artGobbler, 0 ether);

        vm.expectRevert(abi.encodeWithSelector(IGoober.InvalidMultiplier.selector, artGobblerUnrevealed[0]));
        goober.previewSwap(artGobbler, 0, artGobblerUnrevealed, 0 ether);

        bytes memory data;
        vm.expectRevert(abi.encodeWithSelector(IGoober.InvalidMultiplier.selector, 2));
        goober.swap(artGobbler, 100 ether, artGobblerUnrevealed, 0, users[1], data);
        vm.stopPrank();
    }

    // We already check if we can withdraw a multiplier 0 from the pool in another test

    function testUnitMintRevertRatio() public {
        // Safety check to verify starting gobblerPrice is correct.
        assertEq(gobblers.gobblerPrice(), 73013654753028651285);

        /// Add enough Goo to vault to mint a single Gobbler.
        _writeTokenBalance(users[10], address(goo), 1000 ether);

        // Mint the first gobbler
        vm.startPrank(users[10]);
        uint256[] memory artGobbler = new uint256[](1);
        artGobbler[0] = gobblers.mintFromGoo(75 ether, false);
        // Check to see we own the first Gobbler.
        assertEq(gobblers.ownerOf(1), users[10]);
        // Warp a day ahead until we can reveal Gobbler 1.
        vm.warp(block.timestamp + 1 days);
        _setRandomnessAndReveal(1, "seed");
        uint256 gobblerMult = (gobblers.getGobblerEmissionMultiple(artGobbler[0]));
        // Based on our seed, we get a mult of 9 here.
        assertEq(gobblerMult, 9);

        // Safety check to verify new mint price after warp and mint.
        assertEq(gobblers.gobblerPrice(), 52987405899699731484);

        // Pool is setup by depositing 1 gobbler and 55 goo.
        // We do this after warp to not accrue extra goo.
        // Depositing automatically makes the goo virtual.
        uint256 gooTokens = 55 ether;
        goober.deposit(artGobbler, gooTokens, users[10]);
        vm.stopPrank();

        // Tries to mint a gobbler and expects revert.
        // We have enough goo to mint, so should revert due
        // to failing to maintain the conditional ratio.
        vm.startPrank(MINTER);
        vm.expectRevert(
            abi.encodeWithSelector(IGoober.AuctionPriceTooHigh.selector, 7229432954907595640, 6111111111111111111)
        );
        goober.mintGobbler();
        vm.stopPrank();
    }

    function testUnitRevertMintCaller() public {
        vm.startPrank(msg.sender);
        //Revert if not Minter.
        vm.expectRevert();
        goober.mintGobbler();
        vm.stopPrank();
    }

    function testUnitRevertMintGobblerWhenNotMinter() public {
        vm.expectRevert(abi.encodeWithSelector(IGoober.AccessControlViolation.selector, OTHER, MINTER));
        vm.prank(OTHER);
        goober.mintGobbler();
    }

    /*//////////////////////////////////////////////////////////////
    // Flag Gobbler
    //////////////////////////////////////////////////////////////*/

    function testUnitFlagGobbler() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);
        uint256[] memory artGobblers = new uint256[](2);
        uint256[] memory artGobblersTwo = new uint256[](1);
        artGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        artGobblers[1] = gobblers.mintFromGoo(100 ether, true);
        artGobblersTwo[0] = gobblers.mintFromGoo(100 ether, true);
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(3, "seed");
        vm.stopPrank();

        vm.prank(FEE_TO);
        goober.flagGobbler(artGobblersTwo[0], true);

        vm.startPrank(users[1]);
        goober.deposit(artGobblers, 100 ether, users[1]);

        vm.expectRevert(IGoober.InvalidNFT.selector);

        goober.deposit(artGobblersTwo, 100 ether, users[1]);
    }

    function testUnitUnflagGobbler() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);
        uint256[] memory artGobblers = new uint256[](2);
        uint256[] memory artGobblersTwo = new uint256[](1);
        artGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        artGobblers[1] = gobblers.mintFromGoo(100 ether, true);
        artGobblersTwo[0] = gobblers.mintFromGoo(100 ether, true);
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(3, "seed");
        vm.stopPrank();

        vm.startPrank(FEE_TO);
        goober.flagGobbler(artGobblersTwo[0], true);
        goober.flagGobbler(artGobblersTwo[0], false);
        vm.stopPrank();

        // All good
        vm.prank(users[1]);
        goober.deposit(artGobblersTwo, 100 ether, users[1]);
    }

    function testUnitRevertFlagGobblerWhenNotFeeTo() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);
        uint256[] memory artGobblers = new uint256[](2);
        uint256[] memory artGobblersTwo = new uint256[](1);
        artGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        artGobblers[1] = gobblers.mintFromGoo(100 ether, true);
        artGobblersTwo[0] = gobblers.mintFromGoo(100 ether, true);
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(3, "seed");
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(IGoober.AccessControlViolation.selector, OTHER, FEE_TO));

        vm.prank(OTHER);
        goober.flagGobbler(artGobblersTwo[0], true);
    }

    /*//////////////////////////////////////////////////////////////
    // IERC721Receiver
    //////////////////////////////////////////////////////////////*/

    function testUnitRevertOnERC721ReceivedWhenNotGobblerNFT() public {
        MockERC721 mockNFT = new MockERC721("MockERC721", "MOCK");
        mockNFT.mint(users[1], 1);

        vm.expectRevert(IGoober.InvalidNFT.selector);

        vm.prank(users[1]);
        mockNFT.safeTransferFrom(users[1], address(goober), 1);
    }

    function testUnitRevertOnERC721ReceivedWhenDirectlySendingFlaggedGobbler() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);
        uint256[] memory artGobblers = new uint256[](2);
        uint256[] memory artGobblersTwo = new uint256[](1);
        artGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        artGobblers[1] = gobblers.mintFromGoo(100 ether, true);
        artGobblersTwo[0] = gobblers.mintFromGoo(100 ether, true);
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(3, "seed");
        vm.stopPrank();

        vm.prank(FEE_TO);
        goober.flagGobbler(artGobblersTwo[0], true);

        vm.expectRevert(IGoober.InvalidNFT.selector);

        vm.prank(users[1]);
        gobblers.safeTransferFrom(users[1], address(goober), artGobblersTwo[0]);
    }

    function testUnitRevertOnERC721ReceivedWhenDepositingUnrevealedGobbler() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);
        uint256[] memory artGobblers = new uint256[](2);
        uint256[] memory artGobblersTwo = new uint256[](1);
        artGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        artGobblers[1] = gobblers.mintFromGoo(100 ether, true);
        artGobblersTwo[0] = gobblers.mintFromGoo(100 ether, true);

        vm.expectRevert(abi.encodeWithSelector(IGoober.InvalidMultiplier.selector, artGobblersTwo[0]));

        goober.deposit(artGobblersTwo, 100 ether, users[1]);
    }

    /*//////////////////////////////////////////////////////////////
    // Protocol Admin
    //////////////////////////////////////////////////////////////*/

    function testUnitSkimGoo() public {
        _writeTokenBalance(address(goober), address(goo), 1 ether);

        // Precondition checks
        assertEq(goo.balanceOf(FEE_TO), 0);
        assertEq(goo.balanceOf(address(goober)), 1 ether);

        vm.prank(FEE_TO);
        goober.skim(address(goo));

        assertEq(goo.balanceOf(FEE_TO), 1 ether);
        assertEq(goo.balanceOf(address(goober)), 0);
    }

    function testRevertSkimGooWhenNotFeeTo() public {
        vm.expectRevert(abi.encodeWithSelector(IGoober.AccessControlViolation.selector, OTHER, FEE_TO));

        vm.prank(OTHER);
        goober.skim(address(goo));
    }

    function testUnitRevertSkimGooWhenNoGooInContract() public {
        vm.expectRevert(IGoober.NoSkim.selector);

        vm.prank(FEE_TO);
        goober.skim(address(goo));
    }

    function testUnitSetFeeTo() public {
        // Precondition check
        assertEq(goober.feeTo(), FEE_TO);

        vm.prank(FEE_TO);
        goober.setFeeTo(OTHER);

        assertEq(goober.feeTo(), OTHER);
    }

    function testUnitRevertSetFeeToWhenNotAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(IGoober.AccessControlViolation.selector, OTHER, FEE_TO));

        vm.prank(OTHER);
        goober.setFeeTo(address(0xABCD));
    }

    function testUnitRevertSetFeeToWhenZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IGoober.InvalidAddress.selector, address(0)));

        vm.prank(FEE_TO);
        goober.setFeeTo(address(0));
    }

    function testUnitSetMinter() public {
        // Precondition check
        assertEq(goober.minter(), MINTER);

        vm.prank(FEE_TO); // FEE_TO acts as protocol admin
        goober.setMinter(OTHER);

        assertEq(goober.minter(), OTHER);
    }

    function testUnitRevertSetMinterWhenNotAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(IGoober.AccessControlViolation.selector, OTHER, FEE_TO));

        vm.prank(OTHER);
        goober.setMinter(address(0xABCD));
    }

    function testUnitRevertSetMinterWhenZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IGoober.InvalidAddress.selector, address(0)));

        vm.prank(FEE_TO);
        goober.setMinter(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        Events
    //////////////////////////////////////////////////////////////*/

    event VaultMint(address indexed minter, uint256 gooConsumed, uint256 gobblersMinted, bool BalanceTerminated);

    event Deposit(
        address indexed caller, address indexed receiver, uint256[] gobblers, uint256 gooTokens, uint256 fractions
    );

    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256[] gobblers,
        uint256 gooTokens,
        uint256 fractions
    );

    event FeesAccrued(address indexed feeTo, uint256 fractions, bool performanceFee, uint256 _deltaK);

    event Swap(
        address indexed caller,
        address indexed receiver,
        uint256 gooTokensIn,
        uint256 gobblersMultIn,
        uint256 gooTokensOut,
        uint256 gobblerMultOut
    );

    event Sync(uint256 gooBalance, uint256 multBalance);
}
