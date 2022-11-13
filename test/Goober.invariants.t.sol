// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./utils/GooberTest.sol";

import {Warper} from "./actors/Warper.sol";
import {Admin} from "./actors/Admin.sol";
import {User} from "./actors/User.sol";

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

    function invariant_goo_balance() public {
        // I am surprised this passes: isn't it possible for goo
        // balances to decrease with withdrawals?
        uint256 gooBalance = gobblers.gooBalance(address(goober));
        assertGe(gooBalance, prevGooBalance);
        prevGooBalance = gooBalance;
    }

    function invariant_fee_balance() public {
        uint256 gbrFeeBalance = goober.balanceOf(FEE_TO);
        assertGe(gbrFeeBalance, prevGbrFeeBalance);
        prevGbrFeeBalance = gbrFeeBalance;
    }
}
