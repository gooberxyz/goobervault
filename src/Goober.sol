// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "art-gobblers/Goo.sol";
import "art-gobblers/ArtGobblers.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import "./interfaces/IERC20Metadata.sol";
import "./math/UQ112x112.sol";
import "./interfaces/IGoober.sol";
import "./interfaces/IGooberCallee.sol";

// Goober is a Uniswap V2 and EIP-4626 flavored yield vault to optimize gobbler/goo production for Art Gobblers.
// @inheritdoc IERC20Metadata
contract Goober is ReentrancyGuard, ERC20, IGoober {
    // We want to ensure all transfers are safe
    using SafeTransferLib for Goo;
    using SafeTransferLib for ERC20;
    // We use this for fixed point WAD scalar math
    using FixedPointMathLib for uint256;
    // This is the Uniswap V2 112 bit Q math, updated for Solidity 8.
    using UQ112x112 for uint224;

    /*//////////////////////////////////////////////////////////////
    // Immutable storage
    //////////////////////////////////////////////////////////////*/

    /// @notice The goo contract.
    Goo public immutable goo;
    /// @notice The Art Gobblers NFT contract.
    ArtGobblers public immutable artGobblers;

    /// @notice The liquidity locked forever in the pool.
    uint16 private constant MINIMUM_LIQUIDITY = 1e3;
    /// @notice A scalar for scaling up and down to basis points.
    uint16 private constant BPS_SCALAR = 1e4;
    /// @notice The management fee in basis points, charged on deposits.
    uint16 public constant MANAGEMENT_FEE_BPS = 200;
    /// @notice The performance fee in basis points, taken in the form of dilution on the growth of K.
    uint16 public constant PERFORMANCE_FEE_BPS = 1e3;
    /// @notice The average multiplier of a newly minted gobbler.
    /// @notice 7.3294 = weighted avg Mult from mint = ((6*3057) + (7*2621) + (8*2293) + (9*2029))/10000.
    uint32 private constant AVERAGE_MULT_BPS = 73294;

    /*//////////////////////////////////////////////////////////////
    // Mutable storage
    //////////////////////////////////////////////////////////////*/

    // Access control
    /// @notice This is the "admin" address and also where management and performance fees accrue.
    address public feeTo;
    /// @notice This is a privileged actor with the ability to mint gobblers when the pool price is low enough.
    address public minter;

    /// @notice Price oracle accumulator for goo.
    uint256 public priceGooCumulativeLast;
    /// @notice Price oracle accumulator for gobbler multipliers.
    uint256 public priceGobblerCumulativeLast;

    /// @notice sqrt(gooBalance * totalGobblerMultiplier), as of immediately after the most recent liquidity event
    uint112 public kLast;
    /// @notice A counter for debt accrued against performance fees during temporary decreases in K after
    /// @notice mints by the minter, before multipliers are revealed.
    uint112 public kDebt;

    /// @notice Last block timestamp
    /// @dev Yes, the oracle accumulators will reset in 2036.
    uint32 public blockTimestampLast; // uses single storage slot, accessible via getReserves

    /// @notice Flagged NFTs cannot be deposited or swapped in.
    mapping(uint256 => bool) public flagged;

    /*//////////////////////////////////////////////////////////////
    // Constructor
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploy the goober
    /// @param _gobblersAddress - The address of the art gobblers contract.
    /// @param _gooAddress - The address of the Goo contract/token.
    /// @param _feeTo - The admin and address to accrue fees to.
    /// @param _minter - The special address which can trigger mints with pool assets under some conditions.
    constructor(address _gobblersAddress, address _gooAddress, address _feeTo, address _minter)
        ERC20("Goober", "GBR", 18)
    {
        feeTo = _feeTo;
        minter = _minter;
        artGobblers = ArtGobblers(_gobblersAddress);
        goo = Goo(_gooAddress);
    }

    /*//////////////////////////////////////////////////////////////
    // Modifiers
    //////////////////////////////////////////////////////////////*/

    /// @notice This modifier restricts function access to the feeTo address
    modifier onlyFeeTo() {
        if (msg.sender != feeTo) {
            revert AccessControlViolation(msg.sender, feeTo);
        }
        _;
    }

    /// @notice This modifier restricts function access to the minter address
    modifier onlyMinter() {
        if (msg.sender != minter) {
            revert AccessControlViolation(msg.sender, minter);
        }
        _;
    }

    /// @notice This modifier ensures the transaction is included before a specified deadline.
    /// @param deadline - Unix timestamp after which the transaction will revert.
    modifier ensure(uint256 deadline) {
        if (block.timestamp > deadline) {
            revert Expired(block.timestamp, deadline);
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
    // Internal: Non-Mutating
    //////////////////////////////////////////////////////////////*/

    function _shouldMint(uint256 _gooBalance, uint256 _gobblerBalance, uint256 _auctionPrice)
        internal
        pure
        returns (bool mint, uint256 auctionPricePerMult, uint256 poolPricePerMult)
    {
        if (_gooBalance == 0 || _gobblerBalance == 0) {
            revert InsufficientLiquidity(_gooBalance, _gobblerBalance);
        } else if (_auctionPrice == 0) {
            // Unlikely, but avoids divide by zero below.
            mint = true;
        } else {
            if (_gooBalance > _auctionPrice) {
                auctionPricePerMult = (_auctionPrice * BPS_SCALAR) / AVERAGE_MULT_BPS;
                poolPricePerMult = (_gooBalance / _gobblerBalance);
                mint = poolPricePerMult > auctionPricePerMult;
            }
        }
    }

    function _swapCalculations(
        uint256 _gooReserve,
        uint256 _gobblerReserve,
        uint256 _gooBalance,
        uint256 _gobblerBalance,
        uint256 gooOut,
        uint256 multOut,
        bool revertInsufficient
    ) internal pure returns (int256 erroneousGoo, uint256 amount0In, uint256 amount1In) {
        erroneousGoo = 0;
        amount0In = _gooBalance > _gooReserve - gooOut ? _gooBalance - (_gooReserve - gooOut) : 0;
        amount1In = _gobblerBalance > _gobblerReserve - multOut ? _gobblerBalance - (_gobblerReserve - multOut) : 0;
        if (!(amount0In > 0 || amount1In > 0)) {
            revert InsufficientInputAmount(amount0In, amount1In);
        }
        {
            uint256 balance0Adjusted = (_gooBalance * 1000) - (amount0In * 3);
            uint256 balance1Adjusted = (_gobblerBalance * 1000) - (amount1In * 3);
            uint256 adjustedBalanceK = ((balance0Adjusted * balance1Adjusted));
            uint256 expectedK = ((_gooReserve * _gobblerReserve) * 1000 ** 2);

            if (adjustedBalanceK < expectedK) {
                uint256 error = FixedPointMathLib.mulWadUp(
                    FixedPointMathLib.divWadUp(
                        (
                            FixedPointMathLib.mulWadUp(FixedPointMathLib.divWadUp(expectedK, balance1Adjusted), 1)
                                - balance0Adjusted
                        ),
                        997
                    ),
                    1
                );
                if (revertInsufficient) {
                    revert InsufficientGoo(error, adjustedBalanceK, expectedK);
                }
                erroneousGoo += int256(error);
            } else if (adjustedBalanceK > expectedK) {
                erroneousGoo -= int256(
                    FixedPointMathLib.mulWadDown(
                        FixedPointMathLib.divWadDown(
                            (
                                balance0Adjusted
                                    - FixedPointMathLib.mulWadUp(FixedPointMathLib.divWadUp(expectedK, balance1Adjusted), 1)
                            ),
                            1000
                        ),
                        1
                    )
                );
            }
            // Otherwise return 0
        }
    }

    /// @notice Returns various calculations about the value of K.
    function _kCalculations(uint256 _gooBalance, uint256 _gobblerBalance, uint256 _kLast, uint256 _kDebt, bool _roundUp)
        internal
        pure
        returns (uint256 _k, uint256 _kChange, bool _kChangeSign, uint256 _kDelta, uint256 _kDebtChange)
    {
        // Get the present value of k.
        _k = FixedPointMathLib.sqrt(_gooBalance * _gobblerBalance);
        // We don't want to allow the pool to be looted/decommed, ever.
        if (_k == 0) {
            revert MustLeaveLiquidity(_gooBalance, _gobblerBalance);
        }
        // Set delta and change to zero.
        _kDelta = 0;
        _kDebtChange = 0;
        // Did K increase or decrease?
        _kChangeSign = _k > _kLast;
        // Get the gross change in K as a numeric.
        _kChange = _kChangeSign ? _k - _kLast : _kLast - _k;
        // We can't do change math on a fresh pool.
        if (_kLast > 0) {
            // If K went up
            if (_kChangeSign) {
                // Let's offset the debt first if it exists.
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
            // Then we can calculate the delta.
            if (_roundUp) {
                _kDelta = FixedPointMathLib.divWadUp(_kChange, _kLast);
            } else {
                _kDelta = FixedPointMathLib.divWadDown(_kChange, _kLast);
            }
        } else {
            // If kLast -> k is 0 -> n, the change is 100%
            _kDelta = FixedPointMathLib.divWadUp(1, 1);
        }
    }

    /// @notice Returns the management fee given an amount of new fractions created on deposit.
    /// @param fractions New fractions issued for a deposit.
    function _previewManagementFee(uint256 fractions) internal pure returns (uint256 fee) {
        fee = fractions * MANAGEMENT_FEE_BPS / BPS_SCALAR;
    }

    /// @notice Returns a preview of the performance fee.
    /// @param _gooBalance - the goo balance to simulate with.
    /// @param _gobblerBalance - the gobbler balance to simulate with.
    function _previewPerformanceFee(uint256 _gooBalance, uint256 _gobblerBalance)
        internal
        view
        returns (uint256 fee, uint256 kDebtChange, uint256 kDelta)
    {
        // No k, no fee
        uint112 _kLast = kLast;
        uint112 _kDebt = kDebt;
        fee = 0;
        kDebtChange = 0;
        kDelta = 0;
        // If kLast was at 0, then we won't accrue a fee yet, as the pool is brand new.
        if (_kLast > 0) {
            (, uint256 _kChange, bool _kChangeSign, uint256 _kDelta, uint256 _kDebtChange) =
                _kCalculations(_gooBalance, _gobblerBalance, _kLast, _kDebt, false);
            // And then calculate a fee on any remainder.
            if (_kChange > 0 && _kChangeSign) {
                // Calculate the fee as a portion of the total supply at the ration of the _kDelta
                fee = FixedPointMathLib.mulWadDown(totalSupply, _kDelta) * PERFORMANCE_FEE_BPS / BPS_SCALAR;
                // update kDelta return value
                kDelta = uint112(_kDelta);
                // update kDebtChange return value
                kDebtChange = uint112(_kDebtChange);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
    // Internal: Mutating
    //////////////////////////////////////////////////////////////*/

    /// @dev update reserves and, on the first call per block, price accumulators
    /// @param _gooBalance - the new goo balance
    /// @param _gobblerBalance - the new gobbler multiplier
    /// @param _gooReserve - the previous goo reserve
    /// @param _gobblerReserve - the previous gobbler multiplier
    function _update(
        uint256 _gooBalance,
        uint256 _gobblerBalance,
        uint256 _gooReserve,
        uint256 _gobblerReserve,
        bool recordDebt,
        bool updateK
    ) internal {
        /// @dev the accumulators will reset in 2036 due to modulo.
        //slither-disable-next-line weak-prng
        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);

        uint32 timeElapsed;
        unchecked {
            // The time elapsed since the last update
            timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        }

        // These are accumulators which can be used for a goo/gobbler mult twap
        (uint112 castGooReserve, uint112 castGobblerReserve) = (uint112(_gooReserve), uint112(_gobblerReserve));
        if (timeElapsed > 0 && _gooReserve != 0 && _gobblerReserve != 0) {
            unchecked {
                // * never overflows, and + overflow is desired
                priceGooCumulativeLast +=
                    uint256(UQ112x112.encode(uint112(castGooReserve)).uqdiv(castGobblerReserve)) * timeElapsed;
                priceGobblerCumulativeLast +=
                    uint256(UQ112x112.encode(uint112(castGobblerReserve)).uqdiv(uint112(castGooReserve))) * timeElapsed;
            }
        }

        // Update the last update
        blockTimestampLast = blockTimestamp;

        /// @dev We don't store reserves here as they are already stored in other contracts and there was no
        // need to duplicate the state changes

        // Do we need to update historic K values?
        if (updateK || recordDebt) {
            // Get the present K.
            uint112 _k = uint112(FixedPointMathLib.sqrt(_gooBalance * _gobblerBalance));

            // Read the last K from storage.
            uint112 _kLast = kLast;

            // If K decreased, record the debt
            if ((_k < _kLast) && recordDebt) {
                kDebt += _kLast - _k;
            }

            if (updateK) {
                // Update historic k.
                kLast = _k;
            }
        }

        // Emit the reserves which can be used to chart the growth of the pool.
        emit Sync(_gooBalance, _gobblerBalance);
    }

    /// @notice accrues the performance fee on the growth of K if any, offset by kDebt
    /// @param _gooBalance - the balance of Goo to use in calculating the growth of K.
    /// @param _gobblerBalanceMult - the balance of gobbler mult to use in calculating the growth of K.
    function _performanceFee(uint256 _gooBalance, uint256 _gobblerBalanceMult) internal returns (uint256) {
        (uint256 fee, uint256 kDebtChange, uint256 deltaK) = _previewPerformanceFee(_gooBalance, _gobblerBalanceMult);
        if (kDebtChange > 0) {
            kDebt -= uint112(kDebtChange);
        }
        if (fee > 0) {
            _mint(feeTo, fee);
            // Emit info about the fees, and the growth in K
            emit FeesAccrued(feeTo, fee, true, deltaK);
        }
        return fee;
    }

    /// @notice Returns and mints the management fee given an amount of new fractions created on deposit.
    /// @param fractions - New fractions issued for a deposit.
    /// @return fee - the managment fee assesed.
    function _managementFee(uint256 fractions) internal returns (uint256 fee) {
        fee = _previewManagementFee(fractions);
        _mint(feeTo, fee);
        // _deltaK is 0 here because there isn't actually growth in k, this is a deposit.
        emit FeesAccrued(feeTo, fee, false, 0);
    }

    /*//////////////////////////////////////////////////////////////
    // External: Non Mutating
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC721Receiver
    /// @notice Handle deposits of Art Gobblers with an on receive hook, verifying characteristics.
    /// @dev We don't accept non art gobbler NFTs, Art Gobblers with invalid multiples.
    function onERC721Received(address, address, uint256 tokenId, bytes calldata) external view returns (bytes4) {
        /// @dev We only want Art Gobblers NFTs
        if (msg.sender != address(artGobblers)) {
            revert InvalidNFT();
        }
        /// @dev revert on flagged NFTs
        if (flagged[tokenId] == true) {
            revert InvalidNFT();
        }
        /// @dev We want to make sure the gobblers we are getting are revealed.
        uint256 gobMult = artGobblers.getGobblerEmissionMultiple(tokenId);
        if (gobMult < 6) {
            revert InvalidMultiplier(tokenId);
        }
        return IERC721Receiver.onERC721Received.selector;
    }

    /// @inheritdoc IGoober
    function totalAssets() public view returns (uint256 gooTokens, uint256 gobblerMult) {
        gooTokens = artGobblers.gooBalance(address(this));
        gobblerMult = artGobblers.getUserEmissionMultiple(address(this));
    }

    /// @inheritdoc IGoober
    function convertToFractions(uint256 gooTokens, uint256 gobblerMult) external view returns (uint256 fractions) {
        uint256 _totalSupply = totalSupply;
        uint256 kInput = FixedPointMathLib.sqrt(gooTokens * gobblerMult);
        if (_totalSupply > 0) {
            (uint256 gooBalance, uint256 gobblerMultBalance) = totalAssets();
            uint256 kBalance = FixedPointMathLib.sqrt(gooBalance * gobblerMultBalance);
            uint256 kDelta = FixedPointMathLib.divWadDown(kInput, kBalance);
            fractions = FixedPointMathLib.mulWadDown(_totalSupply, kDelta);
        } else {
            fractions = kInput;
        }
    }

    /// @inheritdoc IGoober
    function convertToAssets(uint256 fractions)
        external
        view
        virtual
        returns (uint256 gooTokens, uint256 gobblerMult)
    {
        gooTokens = 0;
        gobblerMult = 0;
        uint256 _totalSupply = totalSupply;
        if (_totalSupply > 0) {
            (gooTokens, gobblerMult) = totalAssets();
            gooTokens = fractions.mulDivDown(gooTokens, _totalSupply);
            gobblerMult = fractions.mulDivDown(gobblerMult, _totalSupply);
        }
    }

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
        // Calculate issuance.
        // Calculate the fractions to burn based on the changes in k.
        // We cast down here to overflow on purpose
        (uint256 _k,,, uint256 _kDelta,) = _kCalculations(
            _gooBalance, _gobblerBalanceMult, FixedPointMathLib.sqrt(_gooReserve * _gobblerReserveMult), 0, true
        );
        if (_totalSupply == 0) {
            // We scale this up to start the fractions at the right order of magnitude at pool launch
            fractions = _k - MINIMUM_LIQUIDITY;
        } else {
            fractions = FixedPointMathLib.mulWadDown(_totalSupply, _kDelta);
        }
        if (fractions == 0) {
            revert InsufficientLiquidityDeposited();
        }
        // Simulate management fee and return preview.
        fractions -= _previewManagementFee(fractions);
    }

    /// @inheritdoc IGoober
    function previewWithdraw(uint256[] calldata gobblers, uint256 gooTokens)
        external
        view
        returns (uint256 fractions)
    {
        // Collect a virtual performance fee.
        (uint256 _gooReserve, uint256 _gobblerReserveMult,) = getReserves();
        uint256 _totalSupply = totalSupply;
        (uint256 pFee,,) = _previewPerformanceFee(_gooReserve, _gobblerReserveMult);
        // Increment virtual total supply.
        _totalSupply += pFee;
        // Simulate transfers.
        uint256 _gooBalance = _gooReserve - gooTokens;
        uint256 _gobblerBalanceMult = _gobblerReserveMult;
        uint256 gobblerMult;
        for (uint256 i = 0; i < gobblers.length; i++) {
            if (artGobblers.ownerOf(gobblers[i]) != address(this)) {
                revert InvalidNFT();
            }
            gobblerMult = artGobblers.getGobblerEmissionMultiple(gobblers[i]);
            if (gobblerMult < 6) {
                revert InvalidMultiplier(gobblers[i]);
            }
            _gobblerBalanceMult -= gobblerMult;
        }
        uint256 _gobblerAmountMult = _gobblerReserveMult - _gobblerBalanceMult;
        if (!(_gobblerAmountMult > 0 || gooTokens > 0)) {
            revert InsufficientLiquidityWithdrawn();
        }
        {
            // Calculate the fractions to burn based on the changes in k.
            (,,, uint256 _kDelta,) = _kCalculations(
                _gooBalance, _gobblerBalanceMult, FixedPointMathLib.sqrt(_gooReserve * _gobblerReserveMult), 0, true
            );
            // Update fractions for return.
            fractions = FixedPointMathLib.mulWadUp(_totalSupply, _kDelta);
        }
    }

    /// @inheritdoc IGoober
    function previewSwap(uint256[] calldata gobblersIn, uint256 gooIn, uint256[] calldata gobblersOut, uint256 gooOut)
        public
        view
        returns (int256 erroneousGoo)
    {
        (uint256 _gooReserve, uint256 _gobblerReserve,) = getReserves();
        // Simulate transfers out
        uint256 _gooBalance = _gooReserve - gooOut;
        uint256 _gobblerBalance = _gobblerReserve;
        uint256 multOut = 0;
        uint256 gobblerMult;
        for (uint256 i = 0; i < gobblersOut.length; i++) {
            if (artGobblers.ownerOf(gobblersOut[i]) != address(this)) {
                revert InvalidNFT();
            }
            gobblerMult = artGobblers.getGobblerEmissionMultiple(gobblersOut[i]);
            if (gobblerMult < 6) {
                revert InvalidMultiplier(gobblersOut[i]);
            }
            _gobblerBalance -= gobblerMult;
            multOut += gobblerMult;
        }
        // Simulate transfers in
        _gooBalance += gooIn;
        for (uint256 i = 0; i < gobblersIn.length; i++) {
            gobblerMult = artGobblers.getGobblerEmissionMultiple(gobblersIn[i]);
            if (gobblerMult < 6) {
                revert InvalidMultiplier(gobblersIn[i]);
            }
            _gobblerBalance += gobblerMult;
        }
        (erroneousGoo,,) =
            _swapCalculations(_gooReserve, _gobblerReserve, _gooBalance, _gobblerBalance, gooOut, multOut, false);
    }

    /*//////////////////////////////////////////////////////////////
    // External: Mutating, Admin
    //////////////////////////////////////////////////////////////*/

    // Access Control

    /// @inheritdoc IGoober
    function setFeeTo(address newFeeTo) external onlyFeeTo {
        if (newFeeTo == address(0)) {
            revert InvalidAddress(newFeeTo);
        }
        feeTo = newFeeTo;
    }

    /// @inheritdoc IGoober
    function setMinter(address newMinter) external onlyFeeTo {
        if (newMinter == address(0)) {
            revert InvalidAddress(newMinter);
        }
        minter = newMinter;
    }

    // Other Privileged Functions

    /// @inheritdoc IGoober
    function mintGobbler() external nonReentrant onlyMinter {
        /// @dev Restricted to onlyMinter to prevent Goo price manipulation.
        /// @dev Prevent reentrancy in case onlyMinter address/keeper is compromised.

        // Get the mint price
        uint256 mintPrice = artGobblers.gobblerPrice();

        // We get the reserves directly here to save some gas
        uint256 gooReserve = artGobblers.gooBalance(address(this));
        uint256 gobblerReserve = artGobblers.getUserEmissionMultiple(address(this));

        // Set an internal balance counter for goo
        uint256 gooBalance = gooReserve;

        // Should we mint?
        (bool mint, uint256 auctionPricePerMult, uint256 poolPricePerMult) =
            _shouldMint(gooBalance, gobblerReserve, mintPrice);

        // We revert here to tell the minter it's calculations are off
        if (mint == false) {
            revert AuctionPriceTooHigh(auctionPricePerMult, poolPricePerMult);
        }

        // Mint Gobblers to pool when our Goo per Mult > Auction (VRGDA) Goo per Mult
        while (mint) {
            // Mint a new gobbler
            //slither-disable-next-line unused-return
            artGobblers.mintFromGoo(mintPrice, true);

            // _shouldMint already prevents an overflow here
            gooBalance -= mintPrice;

            // Emit info about this mint for off chain analysis
            emit VaultMint(msg.sender, auctionPricePerMult, poolPricePerMult, mintPrice);

            // Get the new mint price
            mintPrice = artGobblers.gobblerPrice();

            // Should we mint again?
            (mint, auctionPricePerMult, poolPricePerMult) = _shouldMint(gooBalance, gobblerReserve, mintPrice);
        }

        // Update accumulators, kLast, kDebt
        _update(gooBalance, gobblerReserve, gooReserve, gobblerReserve, true, true);
    }

    /// @inheritdoc IGoober
    function skim(address erc20) external nonReentrant onlyFeeTo {
        /// @dev Contract should never hold ERC20 tokens (only virtual GOO).
        uint256 contractBalance = ERC20(erc20).balanceOf(address(this));
        //slither-disable-next-line dangerous-strict-equalities
        if (contractBalance == 0) {
            revert NoSkim();
        }
        // Transfer the excess goo to the admin for handling.
        ERC20(erc20).safeTransfer(msg.sender, contractBalance);
    }

    function flagGobbler(uint256 tokenId, bool _flagged) external onlyFeeTo {
        flagged[tokenId] = _flagged;
    }

    /*//////////////////////////////////////////////////////////////
    // External: Mutating, Unrestricted
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGoober
    function deposit(uint256[] calldata gobblers, uint256 gooTokens, address receiver)
        public
        nonReentrant
        returns (uint256 fractions)
    {
        // Get reserve balances before they are updated from deposit transfers.
        (uint256 _gooReserve, uint256 _gobblerReserveMult,) = getReserves(); // gas savings

        // Assess performance fee since last transaction.
        _performanceFee(_gooReserve, _gobblerReserveMult);

        // Transfer goo if any.
        if (gooTokens > 0) {
            goo.safeTransferFrom(msg.sender, address(this), gooTokens);
            artGobblers.addGoo(gooTokens);
        }

        // Transfer gobblers if any.
        for (uint256 i = 0; i < gobblers.length; i++) {
            artGobblers.safeTransferFrom(msg.sender, address(this), gobblers[i]);
        }

        // Get the new reserves after transfers in.
        (uint256 _gooBalance, uint256 _gobblerBalanceMult,) = getReserves();
        {
            // Check the total token supply.
            uint256 _totalSupply = totalSupply;

            // Calculate issuance.
            uint256 _kLast = FixedPointMathLib.sqrt(_gooReserve * _gobblerReserveMult);
            // Calculate the fractions to burn based on the changes in k.
            (uint256 _k,,, uint256 _kDelta,) = _kCalculations(_gooBalance, _gobblerBalanceMult, _kLast, 0, true);
            if (_totalSupply == 0) {
                // We scale this up to start the fractions at the right order of magnitude at pool launch
                fractions = _k - MINIMUM_LIQUIDITY;
            } else {
                fractions = FixedPointMathLib.mulWadDown(_totalSupply, _kDelta);
            }
            if (fractions == 0) {
                revert InsufficientLiquidityDeposited();
            }
        }

        // Mint fractions to depositor less management fee.
        fractions -= _managementFee(fractions);
        _mint(receiver, fractions);

        // Update kLast and accumulators.
        _update(_gooBalance, _gobblerBalanceMult, _gooReserve, _gobblerReserveMult, false, true);

        emit Deposit(msg.sender, receiver, gobblers, gooTokens, fractions);
    }

    /// @inheritdoc IGoober
    function safeDeposit(
        uint256[] calldata gobblers,
        uint256 gooTokens,
        address receiver,
        uint256 minFractionsOut,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 fractions) {
        fractions = deposit(gobblers, gooTokens, receiver);

        if (fractions < minFractionsOut) {
            revert MintBelowLimit();
        }
    }

    /// @inheritdoc IGoober
    function withdraw(uint256[] calldata gobblers, uint256 gooTokens, address receiver, address owner)
        public
        nonReentrant
        returns (uint256 fractions)
    {
        // Get starting reserves.
        (uint256 _gooReserve, uint256 _gobblerReserveMult,) = getReserves();
        (uint256 _gooBalance, uint256 _gobblerBalanceMult) = (_gooReserve, _gobblerReserveMult);

        // Assess performance fee since last transaction.
        _performanceFee(_gooReserve, _gobblerReserveMult);

        // Optimistically transfer goo if any.
        if (gooTokens > 0) {
            artGobblers.removeGoo(gooTokens);
            goo.safeTransfer(receiver, gooTokens);
            _gooBalance -= gooTokens;
        }

        // Optimistically transfer gobblers if any.
        uint256 gobblerMult;
        for (uint256 i = 0; i < gobblers.length; i++) {
            gobblerMult = artGobblers.getGobblerEmissionMultiple(gobblers[i]);
            if (gobblerMult < 6) {
                revert InvalidMultiplier(gobblers[i]);
            }
            artGobblers.transferFrom(address(this), receiver, gobblers[i]);
            _gobblerBalanceMult -= gobblerMult;
        }

        // Measure change.
        uint256 _gobblerAmountMult = _gobblerReserveMult - _gobblerBalanceMult;

        if (!(_gobblerAmountMult > 0 || gooTokens > 0)) {
            revert InsufficientLiquidityWithdrawn();
        }

        {
            // Calculate the fractions to burn based on the changes in k.
            // Calculate the fractions to burn based on the changes in k.
            (,,, uint256 _kDelta,) = _kCalculations(
                _gooBalance, _gobblerBalanceMult, FixedPointMathLib.sqrt(_gooReserve * _gobblerReserveMult), 0, true
            );
            uint256 _totalSupply = totalSupply;
            fractions = FixedPointMathLib.mulWadUp(_totalSupply, _kDelta);
        }
        // If we are withdrawing on behalf of someone else, we need to check that they have approved us to do so.
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            // Check that we can withdraw the requested amount of liquidity.
            if (allowed < fractions) {
                revert InsufficientAllowance();
            }

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - fractions;
        }

        // Burn the fractions from owner.
        _burn(owner, fractions);

        // update reserves.
        _update(_gooBalance, _gobblerBalanceMult, _gooReserve, _gobblerReserveMult, false, true);

        emit Withdraw(msg.sender, receiver, owner, gobblers, gooTokens, fractions);
    }

    /// @inheritdoc IGoober
    function safeWithdraw(
        uint256[] calldata gobblers,
        uint256 gooTokens,
        address receiver,
        address owner,
        uint256 maxFractionsIn,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 fractions) {
        fractions = withdraw(gobblers, gooTokens, receiver, owner);

        if (fractions > maxFractionsIn) {
            revert BurnAboveLimit();
        }
    }

    /// @inheritdoc IGoober
    function swap(
        uint256[] calldata gobblersIn,
        uint256 gooIn,
        uint256[] calldata gobblersOut,
        uint256 gooOut,
        address receiver,
        bytes calldata data
    ) public nonReentrant returns (int256) {
        if (!(gooOut > 0 || gobblersOut.length > 0)) {
            revert InsufficientOutputAmount(gooOut, gobblersOut.length);
        }
        if (receiver == address(goo) || receiver == address(artGobblers)) {
            revert InvalidReceiver(receiver);
        }

        // Intermediary struct so we don't get stack too deep
        SwapData memory internalData = SwapData({
            gooReserve: 0,
            gobblerReserve: 0,
            gooBalance: 0,
            gobblerBalance: 0,
            multOut: 0,
            amount0In: 0,
            amount1In: 0,
            erroneousGoo: 0
        });

        (internalData.gooReserve, internalData.gobblerReserve,) = getReserves(); // gas savings

        // Transfer out

        // Optimistically transfer goo if any
        if (gooOut > 0) {
            // This will underflow if we don't have enough goo, by design
            artGobblers.removeGoo(gooOut);
            goo.safeTransfer(receiver, gooOut);
        }

        // Optimistically transfer gobblers if any
        if (gobblersOut.length > 0) {
            for (uint256 i = 0; i < gobblersOut.length; i++) {
                uint256 gobblerMult = artGobblers.getGobblerEmissionMultiple(gobblersOut[i]);
                if (gobblerMult < 6) {
                    revert InvalidMultiplier(gobblersOut[i]);
                }
                internalData.multOut += gobblerMult;
                artGobblers.transferFrom(address(this), receiver, gobblersOut[i]);
            }
        }

        // Flash loan call out
        // We only need to send the data, because all the other action happens here.
        if (data.length > 0) IGooberCallee(receiver).gooberCall(data);

        // Transfer in

        // Transfer in goo if any
        if (gooIn > 0) {
            goo.safeTransferFrom(msg.sender, address(this), gooIn);
            artGobblers.addGoo(gooIn);
        }

        // Transfer in gobblers if any
        for (uint256 i = 0; i < gobblersIn.length; i++) {
            artGobblers.safeTransferFrom(msg.sender, address(this), gobblersIn[i]);
        }

        (internalData.gooBalance, internalData.gobblerBalance,) = getReserves();

        (internalData.erroneousGoo, internalData.amount0In, internalData.amount1In) = _swapCalculations(
            internalData.gooReserve,
            internalData.gobblerReserve,
            internalData.gooBalance,
            internalData.gobblerBalance,
            gooOut,
            internalData.multOut,
            true
        );
        // Update oracle.
        _update(
            internalData.gooBalance,
            internalData.gobblerBalance,
            internalData.gooReserve,
            internalData.gobblerReserve,
            false,
            false
        );
        emit Swap(msg.sender, receiver, internalData.amount0In, internalData.amount1In, gooOut, internalData.multOut);
        return internalData.erroneousGoo;
    }

    /// @inheritdoc IGoober
    function safeSwap(
        uint256 erroneousGooAbs,
        uint256 deadline,
        uint256[] calldata gobblersIn,
        uint256 gooIn,
        uint256[] calldata gobblersOut,
        uint256 gooOut,
        address receiver,
        bytes calldata data
    ) external ensure(deadline) returns (int256 erroneousGoo) {
        erroneousGoo = previewSwap(gobblersIn, gooIn, gobblersOut, gooOut);
        if (erroneousGoo < 0) {
            uint256 additionalGooOut = uint256(-erroneousGoo);
            if (additionalGooOut > erroneousGooAbs) {
                revert ExcessiveErroneousGoo(additionalGooOut, erroneousGooAbs);
            }
            gooOut += additionalGooOut;
        } else if (erroneousGoo > 0) {
            uint256 additionalGooIn = uint256(erroneousGoo);
            if (additionalGooIn > erroneousGooAbs) {
                revert ExcessiveErroneousGoo(additionalGooIn, erroneousGooAbs);
            }
            gooIn += additionalGooIn;
        }

        erroneousGoo = swap(gobblersIn, gooIn, gobblersOut, gooOut, receiver, data);
    }
}
