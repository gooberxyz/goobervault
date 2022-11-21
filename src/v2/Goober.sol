// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "art-gobblers/Goo.sol";
import "art-gobblers/ArtGobblers.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import "./math/UQ112x112.sol";

import "./interfaces/IGoober.sol";

/// @title goober_xyz
/// @author XYZ
/// @notice Goober is an experimental Uniswap V2 and EIP-4626 flavored vault to optimize Art
/// @notice production for the decentralized art factory by Justin Roiland and Paradigm.
contract Goober is ReentrancyGuard, ERC20, IGoober {
    //

    // We want to ensure all ERC721 transfers are safe.
    using SafeTransferLib for Goo;
    // We want to ensure all ERC20 transfers are safe.
    using SafeTransferLib for ERC20;
    // We use this for fixed point WAD scalar math.
    using FixedPointMathLib for uint256;
    // This is the Uniswap V2 112 bit Q math, updated for Solidity 8.
    using UQ112x112 for uint224;

    /*//////////////////////////////////////////////////////////////
    //  Immutable storage
    //////////////////////////////////////////////////////////////*/

    /// @notice The Goo contract.
    Goo public immutable goo;
    /// @notice The Art Gobblers NFT contract.
    ArtGobblers public immutable artGobblers;

    /// @notice The liquidity locked forever in the pool.
    uint16 private constant MINIMUM_LIQUIDITY = 1e3;
    /// @notice A scalar for scaling up and down to basis points.
    uint16 private constant BPS_SCALAR = 1e4;
    /// @notice The management fee in basis points, charged on deposits.
    uint16 public constant MANAGEMENT_FEE_BPS = 200;
    /// @notice The performance fee in basis points, taken in the form
    /// @notice of dilution on the growth of sqrt(gooBalance * gobblerMult),
    /// @notice
    uint16 public constant PERFORMANCE_FEE_BPS = 1e3;
    /// @notice The average multiplier of a newly minted gobbler.
    /// @notice 7.3294 = weighted avg. multiplier from mint probabilities,
    /// @notice derived from: ((6*3057) + (7*2621) + (8*2293) + (9*2029)) / 10000.
    uint32 private constant AVERAGE_MULT_BPS = 73294;

    /*//////////////////////////////////////////////////////////////
    //  Mutable storage
    //////////////////////////////////////////////////////////////*/

    // Access control
    /// @notice This is the "admin" address and also where management and performance fees accrue.
    address public feeTo;
    /// @notice This is a privileged actor with the ability to mint gobblers when the pool price is low enough.
    address public minter;

    /// @notice K, as of immediately after the most recent liquidity event.
    uint112 public kLast;
    /// @notice A counter for debt accrued against performance fees during the temporary decreases in K
    /// @notice after mints by the minter, before gobblers' multipliers are revealed.
    uint112 public kDebt;

    /// @notice Last block timestamp
    /// @dev Yes, the oracle accumulators will reset in 2036.
    uint32 public blockTimestampLast; // uses single storage slot, accessible via getReserves

    /*//////////////////////////////////////////////////////////////
    //  Constructor
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploys the goober contract.
    /// @param _gobblersAddress - The address of the Art Gobblers contract.
    /// @param _gooAddress - The address of the Goo contract/token.
    /// @param _feeTo - The admin and address to accrue fees to.
    /// @param _minter - The address able to mint gobblers to the pool.
    /// @notice The minter is able to mint using pool assets based on conditions defined in the mintGobbler function.
    constructor(address _gobblersAddress, address _gooAddress, address _feeTo, address _minter)
        ERC20("Goober", "GBR", 18)
    {
        feeTo = _feeTo;
        minter = _minter;
        artGobblers = ArtGobblers(_gobblersAddress);
        goo = Goo(_gooAddress);
    }

    /*//////////////////////////////////////////////////////////////
    //  Accounting
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGoober
    function getReserves()
        public
        view
        returns (uint256 _gooReserve, uint256 _gobblerReserve, uint32 _blockTimestampLast)
    {
        _gooReserve = artGobblers.gooBalance(address(this));
        _gobblerReserve = artGobblers.getUserEmissionMultiple(address(this));
        _blockTimestampLast = blockTimestampLast;
    }

    /*//////////////////////////////////////////////////////////////
    //  Deposit
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGoober
    function previewDeposit(uint256[] calldata gobblers, uint256 gooTokens) external view returns (uint256 fractions) {
        // Collect a virtual performance fee.
        (uint256 _gooReserve, uint256 _gobblerReserveMult,) = getReserves();
        (uint256 pFee,,) = _previewPerformanceFee(_gooReserve, _gobblerReserveMult);
        // Increment virtual total supply by performance fee.
        uint256 _totalSupply = pFee + totalSupply;
        // Simulate transfers.
        uint256 _gooBalance = gooTokens + _gooReserve;
        uint256 _gobblerBalanceMult = _gobblerReserveMult;
        for (uint256 i = 0; i < gobblers.length; i++) {
            _gobblerBalanceMult += artGobblers.getGobblerEmissionMultiple(gobblers[i]);
        }
        // Calculate the fractions to create based on the changes in K.
        (uint256 _k,,, uint256 _kDelta,) = _kCalculations(
            _gooBalance, _gobblerBalanceMult, FixedPointMathLib.sqrt(_gooReserve * _gobblerReserveMult), 0, true
        );
        if (_totalSupply == 0) {
            // We want to start the fractions at the right order of magnitude at init, so
            // we scale this by 1e9 to simulate 2 ERC20s, because Gobbler mult are integers
            // rather than 1e18 ERC20s from the Uni V2 design.
            fractions = _k * 1e9 - MINIMUM_LIQUIDITY;
        } else {
            fractions = FixedPointMathLib.mulWadDown(_totalSupply, _kDelta);
        }
        if (fractions == 0) {
            revert InsufficientLiquidityDeposited();
        }
        // Simulate management fee and return preview.
        fractions -= _previewManagementFee(fractions);
    }

    /*//////////////////////////////////////////////////////////////
    //  Fee Math
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns various calculations about the value of K.
    function _kCalculations(uint256 _gooBalance, uint256 _gobblerBalance, uint256 _kLast, uint256 _kDebt, bool _roundUp)
        internal
        pure
        returns (uint256 _k, uint256 _kChange, bool _kChangeSign, uint256 _kDelta, uint256 _kDebtChange)
    {
        // Get the present value of K.
        _k = FixedPointMathLib.sqrt(_gooBalance * _gobblerBalance);
        // We don't want to allow the pool to be decommed, ever.
        if (_k == 0) {
            revert MustLeaveLiquidity(_gooBalance, _gobblerBalance);
        }
        // Set delta and debt change to zero.
        _kDelta = 0;
        _kDebtChange = 0;
        // Did K increase or decrease?
        _kChangeSign = _k > _kLast;
        // Get the gross change in K as a numeric.
        _kChange = _kChangeSign ? _k - _kLast : _kLast - _k;
        // We can't do change math on a fresh pool.
        if (_kLast > 0) {
            // If K went up,
            if (_kChangeSign) {
                // let's offset the debt first if it exists;
                if (_kDebt > 0) {
                    if (_kChange <= _kDebt) {
                        _kDebtChange += _kChange;
                        _kChange = 0;
                    } else {
                        _kDebtChange += _kDebt;
                        _kChange -= _kDebt;
                    }
                }
            }
            // then we can calculate the delta.
            if (_roundUp) {
                _kDelta = FixedPointMathLib.divWadUp(_kChange, _kLast);
            } else {
                _kDelta = FixedPointMathLib.divWadDown(_kChange, _kLast);
            }
        } else {
            // If kLast -> k is 0 -> n, then the delta is 100%.
            _kDelta = FixedPointMathLib.divWadUp(1, 1);
        }
    }

    /// @notice Returns the management fee given an amount of new fractions created on deposit.
    /// @param fractions New fractions issued for a deposit.
    function _previewManagementFee(uint256 fractions) internal pure returns (uint256 fee) {
        fee = fractions * MANAGEMENT_FEE_BPS / BPS_SCALAR;
    }

    /// @notice Returns a preview of the performance fee.
    /// @param _gooBalance - The Goo balance to simulate with.
    /// @param _gobblerBalance - The Gobbler balance to simulate with.
    function _previewPerformanceFee(uint256 _gooBalance, uint256 _gobblerBalance)
        internal
        view
        returns (uint256 fee, uint256 kDebtChange, uint256 kDelta)
    {
        // No K, no fee.
        uint112 _kLast = kLast;
        uint112 _kDebt = kDebt;
        fee = 0;
        kDebtChange = 0;
        kDelta = 0;
        // If kLast was at 0, then we won't accrue a fee yet, as the pool is uninitialized.
        if (_kLast > 0) {
            (, uint256 _kChange, bool _kChangeSign, uint256 _kDelta, uint256 _kDebtChange) =
                _kCalculations(_gooBalance, _gobblerBalance, _kLast, _kDebt, false);
            // Then, determine a fee on any remainder after offsetting outstanding debt.
            if (_kChange > 0 && _kChangeSign) {
                // Calculate the fee as a portion of the the growth of total supply as determined by kDelta.
                fee = FixedPointMathLib.mulWadDown(totalSupply, _kDelta) * PERFORMANCE_FEE_BPS / BPS_SCALAR;
                // Update kDelta return value.
                kDelta = uint112(_kDelta);
                // Update kDebtChange return value.
                kDebtChange = uint112(_kDebtChange);
            }
        }
    }
}
