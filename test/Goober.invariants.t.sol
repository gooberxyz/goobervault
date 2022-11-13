// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./utils/GooberTest.sol";

import {Timekeeper} from "./actors/Timekeeper.sol";
import {Admin, Minter} from "./actors/Admin.sol";
import {User} from "./actors/User.sol";
import "./actors/Timekeeper.sol";

// TODO write invariant tests that use actors, with various assets and actions

contract GooberInvariantsTest is GooberTest {
    Timekeeper internal timekeeper;
    Admin internal admin;
    User internal user;
    Minter internal minter;

    address[] private _targetContracts;

    uint256 internal prevGooBalance;
    uint256 internal prevGbrFeeBalance;

    function targetContracts() public view returns (address[] memory targetContracts_) {
        require(_targetContracts.length != uint256(0), "NO_TARGET_CONTRACTS");
        return _targetContracts;
    }

    function _addTargetContract(address newTargetContract_) internal {
        _targetContracts.push(newTargetContract_);
    }

    function setUp() public override {
        super.setUp();

        user = new User({
            _goo: goo,
            _gobblers: gobblers,
            _goober: goober,
            _vrfCoordinator: vrfCoordinator,
            _randProvider: randProvider
        });

        admin = new Admin({
            _goo: goo,
            _gobblers: gobblers,
            _goober: goober,
            _vrfCoordinator: vrfCoordinator,
            _randProvider: randProvider
        });

        minter = new Minter({
        _goo: goo,
        _gobblers: gobblers,
        _goober: goober,
        _vrfCoordinator: vrfCoordinator,
        _randProvider: randProvider
        });

        timekeeper = new Timekeeper();

        _addTargetContract(address(user));
        _addTargetContract(address(admin));
        _addTargetContract(address(minter));
        _addTargetContract(address(timekeeper));
    }

    /// @dev Fee balances only go up.
    function testInvariantFeeBalanceIncreases() public {
        uint256 gbrFeeBalance = goober.balanceOf(FEE_TO);
        assertGe(gbrFeeBalance, prevGbrFeeBalance);
        prevGbrFeeBalance = gbrFeeBalance;
    }

    /// @dev Goober vault multiplier = sum of deposited Gobbler multipliers
    function testInvariantVaultMulEqualsSumOfEmissionMultiples() public {
        uint256 gooberMul = gobblers.getUserEmissionMultiple(address(goober));
        uint256[] memory depositedGobblers = user.getDepositedGobblers();
        uint256 depositedMulSum;
        for (uint256 i; i < depositedGobblers.length; ++i) {
            depositedMulSum += gobblers.getGobblerEmissionMultiple(depositedGobblers[i]);
        }
        assertEq(gooberMul, depositedMulSum);
    }

    /// @dev Goober vault gobbler reserve = sum of deposited + minted gobblers
    function testInvariantGobblerReserveEqualsVaultMultiplier() public {
        (, uint112 gobblerReserve,) = goober.getReserves();
        uint256 gooberMul = gobblers.getUserEmissionMultiple(address(goober));
        assertEq(gooberMul, gobblerReserve);
    }

    /// @dev Goober vault gobbler reserve = sum of deposited + minted gobblers
    function testInvariantGobblerReserve() public {
        (, uint112 gobblerReserve,) = goober.getReserves();

        uint256[] memory depositedGobblers = user.getDepositedGobblers();
        uint256 depositedMulSum;
        for (uint256 i; i < depositedGobblers.length; ++i) {
            depositedMulSum += gobblers.getGobblerEmissionMultiple(depositedGobblers[i]);
        }
        assertEq(depositedMulSum, gobblerReserve);
    }
}
