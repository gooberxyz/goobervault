// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./utils/GooberTest.sol";

import {Warper} from "./actors/Warper.sol";
import {Admin} from "./actors/Admin.sol";
import {User} from "./actors/User.sol";

// TODO write invariant tests that use actors, with various assets and actions

contract GooberInvariantsTest is GooberTest {
    Warper internal warper;
    Admin internal admin;
    User internal user;

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

        warper = new Warper();

        _addTargetContract(address(user));
        _addTargetContract(address(admin));
        _addTargetContract(address(warper));
    }

    /// @dev Fee balances only go up.
    function invariant_feeBalanceIncreases() public {
        uint256 gbrFeeBalance = goober.balanceOf(FEE_TO);
        assertGe(gbrFeeBalance, prevGbrFeeBalance);
        prevGbrFeeBalance = gbrFeeBalance;
    }

    /// @dev Goober vault multiplier = sum of deposited Gobbler multipliers
    function invariant_vaultMulEqualsSumOfEmissionMultiples() public {
        uint256 gooberMul = gobblers.getUserEmissionMultiple(address(goober));
        uint256[] memory depositedGobblers = user.getDepositedGobblers();
        uint256 depositedMulSum;
        for (uint256 i; i < depositedGobblers.length; ++i) {
            depositedMulSum += gobblers.getGobblerEmissionMultiple(depositedGobblers[i]);
        }
        assertEq(gooberMul, depositedMulSum);
    }

    /// @dev Goober vault gobbler reserve = sum of deposited + minted gobblers
    function invariant_gobblerReserveEqualsVaultMultiplier() public {
        (, uint112 gobblerReserve,) = goober.getReserves();
        uint256 gooberMul = gobblers.getUserEmissionMultiple(address(goober));
        assertEq(gooberMul, gobblerReserve);
    }

    /// @dev Goober vault gobbler reserve = sum of deposited + minted gobblers
    function invariant_gobblerReserve() public {
        (, uint112 gobblerReserve,) = goober.getReserves();

        uint256[] memory depositedGobblers = user.getDepositedGobblers();
        uint256 depositedMulSum;
        for (uint256 i; i < depositedGobblers.length; ++i) {
            depositedMulSum += gobblers.getGobblerEmissionMultiple(depositedGobblers[i]);
        }
        assertEq(depositedMulSum, gobblerReserve);
    }
}
