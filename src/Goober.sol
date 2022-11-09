// SPDX-License-Identifier: MIT
// TODO(Should this be BUSL?)

pragma solidity ^0.8.17;

import "art-gobblers/Goo.sol";
import "art-gobblers/ArtGobblers.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import "./math/UQ112x112.sol";
import "./interfaces/IGoober.sol";
import "./interfaces/IGooberCallee.sol";

// Goober is a Uniswap V2 and EIP-4626 flavored yield vault to optimize gobbler/goo production.
contract Goober is ReentrancyGuard, ERC20, IGoober {
    // We want to ensure all transfers are safe
    using SafeTransferLib for Goo;
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

    // TODO(Can we engineer this out?)
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

    // TODO(Can these be 112 bit to save a storage slot?)
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
    uint32 private blockTimestampLast; // uses single storage slot, accessible via getReserves

    /// @notice Flagged NFTs cannot be deposited or swapped in.
    mapping(uint256 => bool) public flagged;

    /*//////////////////////////////////////////////////////////////
    // Constructor
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploy the goober
    /// @param _gobblersAddress The address of the art gobblers contract.
    /// @param _gooAddress The address of the Goo contract/token.
    /// @param _feeTo The admin and address to accrue fees to.
    /// @param _minter The special address which can trigger mints with pool assets under some conditions.
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

    /*//////////////////////////////////////////////////////////////
    // Internal: Non-Mutating
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the management fee given an amount of new fractions created on deposit.
    /// @param fractions New fractions issued for a deposit.
    function _previewManagementFee(uint256 fractions) internal pure returns (uint256 fee) {
        fee = fractions * MANAGEMENT_FEE_BPS / BPS_SCALAR;
    }

    function _previewPerformanceFee(uint112 _gooBalance, uint112 _gobblerBalanceMult)
        internal
        view
        returns (uint256 fee, uint112 kDebtChange, uint256 deltaK)
    {
        // Read the last K value
        uint112 _kLast = kLast;
        // Check if we have any kDebt outstanding from mints
        uint112 _kDebt = kDebt;
        // Calculate the present K
        uint112 _k = uint112(FixedPointMathLib.sqrt(_gooBalance * _gobblerBalanceMult));
        // Did K increase?
        bool _kIncrease = _k > kLast;
        // Get the gross change in K as a numeric
        uint112 _kChange = _kIncrease ? _k - _kLast : _kLast - _k;
        // No k, no fee
        fee = 0;
        kDebtChange = 0;
        deltaK = 0;
        // If kLast was at 0, then we won't accrue a fee yet, as the pool is brand new.
        if (_kLast > 0) {
            // K grew
            if (_kIncrease) {
                // Let's offset the debt first if it exists
                if (_kDebt > 0) {
                    if (_kChange <= _kDebt) {
                        kDebtChange += _kChange;
                        _kChange = 0;
                    } else {
                        kDebtChange += _kDebt;
                        _kChange -= _kDebt;
                    }
                }
                // And then calculate a fee on any remainder
                if (_kChange > 0) {
                    // Get the change in K counting towards a performance fee as a ratio of the total
                    deltaK = FixedPointMathLib.divWadDown(_kChange, _kLast);
                    // Calculate the fee as a portion of the total supply at the ration of the _deltaK
                    fee = FixedPointMathLib.mulWadDown(totalSupply, deltaK) * PERFORMANCE_FEE_BPS / BPS_SCALAR;
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
    // Internal: Mutating
    //////////////////////////////////////////////////////////////*/

    /// @dev update reserves and, on the first call per block, price accumulators
    /// @param _gooBalance the new goo balance
    /// @param _gobblerBalance the new gobbler multiplier
    /// @param _gooReserve the previous goo reserve
    /// @param _gobblerReserve the previous gobbler multiplier
    function _update(
        uint256 _gooBalance,
        uint256 _gobblerBalance,
        uint112 _gooReserve,
        uint112 _gobblerReserve,
        bool recordDebt
    ) internal {
        // Check if the reserves will overflow
        /// @dev on the off chance they do, the feeTo has an escape valve in skimGoo.
        require(_gooBalance <= type(uint112).max && _gobblerBalance <= type(uint112).max, "Goober: OVERFLOW");

        /// @dev the accumulators will reset in 2036 due to modulo.
        //slither-disable-next-line weak-prng
        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);

        uint32 timeElapsed;
        unchecked {
            // The time elapsed since the last update
            timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        }

        // These are accumulators which can be used for a goo/gobbler mult twap
        if (timeElapsed > 0 && _gooReserve != 0 && _gobblerReserve != 0) {
            unchecked {
                // * never overflows, and + overflow is desired
                priceGooCumulativeLast += uint256(UQ112x112.encode(_gobblerReserve).uqdiv(_gooReserve)) * timeElapsed;
                priceGobblerCumulativeLast +=
                    uint256(UQ112x112.encode(_gooReserve).uqdiv(_gobblerReserve)) * timeElapsed;
            }
        }

        // Update the last update
        blockTimestampLast = blockTimestamp;

        /// @dev We don't store reserves here as they are already stored in other contracts and there was no
        // need to duplicate the state changes

        // Get the present K.
        uint112 _k = uint112(FixedPointMathLib.sqrt(_gooBalance * _gobblerBalance));

        // Read the last K from storage.
        uint112 _kLast = kLast;

        // If K decreased, record the debt
        if ((_k < _kLast) && recordDebt) {
            kDebt += _kLast - _k;
        }

        // Update historic k.
        kLast = _k;

        // Emit the reserves which can be used to chart the growth of the pool.
        emit Sync(uint112(_gooBalance), uint112(_gobblerBalance));
    }

    /// @notice accrues the performance fee on the growth of K if any, offset by kDebt
    /// @param _gooBalance the balance of Goo to use in calculating the growth of K.
    /// @param _gobblerBalanceMult the balance of gobbler mult to use in calculating the growth of K.
    function _performanceFee(uint112 _gooBalance, uint112 _gobblerBalanceMult) internal returns (uint256) {
        (uint256 fee, uint112 kDebtChange, uint256 deltaK) = _previewPerformanceFee(_gooBalance, _gobblerBalanceMult);
        if (kDebtChange > 0) {
            kDebt -= kDebtChange;
        }
        if (fee > 0) {
            _mint(feeTo, fee);
            // Emit info about the fees, and the growth in K
            emit FeesAccrued(feeTo, fee, true, deltaK);
        }
        return fee;
    }

    /// @notice Returns and mints the management fee given an amount of new shares created on deposit.
    /// @param fractions New shares issued for a deposit.
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

    /// @return gooTokens the total amount of goo owned
    /// @return gobblerMult the total multiple of all gobblers owned
    function totalAssets() public view returns (uint256 gooTokens, uint256 gobblerMult) {
        gobblerMult = artGobblers.getUserEmissionMultiple(address(this));
        gooTokens = goo.balanceOf(address(this)) + artGobblers.gooBalance(address(this));
    }

    /// @return _gooReserve the total amount of goo in the tank for all owned gobblers
    /// @return _gobblerReserve the total multiplier of all gobblers owned
    /// @return _blockTimestampLast the last time that the reserves were updated
    function getReserves()
        public
        view
        returns (uint112 _gooReserve, uint112 _gobblerReserve, uint32 _blockTimestampLast)
    {
        _gooReserve = uint112(artGobblers.gooBalance(address(this)));
        _gobblerReserve = uint112(artGobblers.getUserEmissionMultiple(address(this)));
        _blockTimestampLast = blockTimestampLast;
    }

    // Mutating external/public functions

    /// @notice Previews a deposit of the supplied gobblers goo.
    /// @param gobblers - array of gobbler ids
    /// @param gooTokens - amount of goo to withdraw
    /// @return fractions - amount of GBR minted
    function previewDeposit(uint256[] calldata gobblers, uint256 gooTokens) public view returns (uint256 fractions) {
        fractions = 0;
        // Collect a virtual performance fee
        (uint112 _gooReserve, uint112 _gobblerReserveMult,) = getReserves();
        uint256 _totalSupply = totalSupply;
        (uint256 pFee,,) = _previewPerformanceFee(_gooReserve, _gobblerReserveMult);
        // Increment virtual total supply
        _totalSupply += pFee;
        // Simulate transfers
        uint256 _gooBalance = gooTokens + _gooReserve;
        uint256 _gobblerBalanceMult = _gobblerReserveMult;
        for (uint256 i = 0; i < gobblers.length; i++) {
            _gobblerBalanceMult += artGobblers.getGobblerEmissionMultiple(gobblers[i]);
        }
        uint256 gobblerAmountMult = _gobblerBalanceMult - _gobblerReserveMult;
        // Calculate issuance
        if (_totalSupply == 0) {
            fractions = FixedPointMathLib.sqrt(gooTokens * gobblerAmountMult) - MINIMUM_LIQUIDITY;
        } else {
            uint256 _kLast = FixedPointMathLib.sqrt(_gooReserve * _gobblerReserveMult);
            uint256 _k = FixedPointMathLib.sqrt(_gooBalance * _gobblerBalanceMult);
            uint256 _deltaK = FixedPointMathLib.divWadDown(_k - _kLast, _kLast);
            fractions = FixedPointMathLib.mulWadDown(_totalSupply, _deltaK);
        }
        require(fractions > 0, "Goober: INSUFFICIENT_LIQUIDITY_MINTED");
        // Simulate management fee and return preview
        fractions -= _previewManagementFee(fractions);
    }

    /// @notice Previews a withdraw of the requested gobblers and goo tokens from the vault.
    /// @param gobblers - array of gobbler ids
    /// @param gooTokens - amount of goo to withdraw
    /// @return fractions - amount of shares that have been withdrawn
    function previewWithdraw(uint256[] calldata gobblers, uint256 gooTokens)
        external
        view
        returns (uint256 fractions)
    {
        // Collect a virtual performance fee
        (uint112 _gooReserve, uint112 _gobblerReserveMult,) = getReserves();
        uint256 _totalSupply = totalSupply;
        (uint256 pFee,,) = _previewPerformanceFee(_gooReserve, _gobblerReserveMult);
        // Increment virtual total supply
        _totalSupply += pFee;
        // Simulate transfers
        uint112 _gooBalance = _gooReserve - uint112(gooTokens);
        uint112 _gobblerBalanceMult = _gobblerReserveMult;
        uint256 gobblerMult;
        for (uint256 i = 0; i < gobblers.length; i++) {
            gobblerMult = artGobblers.getGobblerEmissionMultiple(gobblers[i]);
            if (gobblerMult < 6) {
                revert InvalidMultiplier(gobblers[i]);
            }
            if (artGobblers.ownerOf(gobblers[i]) != address(this)) {
                revert InvalidNFT();
            }
            _gobblerBalanceMult -= uint112(gobblerMult);
        }
        uint112 _gobblerAmountMult = _gobblerReserveMult - _gobblerBalanceMult;
        require(_gobblerAmountMult > 0 || gooTokens > 0, "Goober: INSUFFICIENT LIQUIDITY WITHDRAW");
        {
            // Calculate the fractions to burn based on the changes in k.
            uint256 _kLast = FixedPointMathLib.sqrt(_gooReserve * _gobblerReserveMult);
            uint256 _k = FixedPointMathLib.sqrt(_gooBalance * _gobblerBalanceMult);
            // We don't want to allow the pool to be looted/decommed, ever
            require(_k > 0, "Goober: MUST LEAVE LIQUIDITY");
            uint256 _deltaK = FixedPointMathLib.divWadUp(_kLast - _k, _kLast);
            fractions = FixedPointMathLib.mulWadUp(_totalSupply, _deltaK);
        }
    }

    /*//////////////////////////////////////////////////////////////
    // External: Mutating, Admin
    //////////////////////////////////////////////////////////////*/

    // Access Control

    /// @inheritdoc IGoober
    function setFeeTo(address newFeeTo) public onlyFeeTo {
        if (newFeeTo == address(0)) {
            revert InvalidAddress(newFeeTo);
        }
        feeTo = newFeeTo;
    }

    /// @inheritdoc IGoober
    function setMinter(address newMinter) public onlyFeeTo {
        if (newMinter == address(0)) {
            revert InvalidAddress(newMinter);
        }
        minter = newMinter;
    }

    // Other Privileged Functions

    // @notice Mints Gobblers using the vault's virtual reserves of Goo if the pool's goo per mult is lower than VRGDA goo per mult.
    function mintGobbler() public nonReentrant onlyMinter {
        // This function is restricted to onlyMinter because we don't want
        // the general public to use it to manipulate the goo price.

        // Get the mint price
        uint256 mintPrice = artGobblers.gobblerPrice();
        // We get the reserves directly here to save some gas
        uint112 gooReserve = uint112(artGobblers.gooBalance(address(this)));
        uint256 gooBalance = gooReserve;
        uint112 gobblerReserve = uint112(artGobblers.getUserEmissionMultiple(address(this)));

        // Should we mint?
        bool mint = (gooBalance / gobblerReserve) <= (mintPrice * BPS_SCALAR) / AVERAGE_MULT_BPS;
        // Mint Gobblers to pool when our Goo per Mult < Auction Goo per Mult.
        while (mint) {
            if (gooBalance >= mintPrice) {
                gooBalance -= mintPrice;
                artGobblers.mintFromGoo(mintPrice, true);
                // TODO(Can we calculate the increase without an sload here?)
                mintPrice = artGobblers.gobblerPrice();
                mint = (gooBalance / gobblerReserve) <= (mintPrice * BPS_SCALAR) / AVERAGE_MULT_BPS;
            } else {
                mint = false;
            }
        }
        // Update accumulators, kLast, kDebt
        _update(uint112(gooBalance), gobblerReserve, gooReserve, gobblerReserve, true);
    }

    /// @notice Admin function for skimming any goo that may be in the wrong place, or overflown.
    function skimGoo() public nonReentrant onlyFeeTo {
        /// @dev if goo has overflown uint112 in the tank, this is the escape valve
        uint256 gooTankBalance = artGobblers.gooBalance(address(this));
        // This will unstick the contract, in the unlikely case this occurs
        if (gooTankBalance >= type(uint112).max) {
            artGobblers.removeGoo(type(uint112).max + 1);
        }
        /// @dev Contract should never hold GOO tokens (only virtual GOO).
        uint256 contractGooBalance = goo.balanceOf(address(this));
        if (contractGooBalance == 0) {
            revert NoSkim();
        }
        // Transfer the excess goo to the admin for handling
        goo.safeTransfer(msg.sender, contractGooBalance);
        (uint112 _gooReserve, uint112 _gobblerReserveMult,) = getReserves();
        _update(_gooReserve, _gobblerReserveMult, _gooReserve, _gobblerReserveMult, false);
    }

    function flagGobbler(uint256 tokenId, bool _flagged) public onlyFeeTo {
        flagged[tokenId] = _flagged;
    }

    /*//////////////////////////////////////////////////////////////
    // External: Mutating, Unrestricted
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposits the supplied gobblers/goo from the owner and mints GBR to the receiver
    /// @param gobblers - array of gobbler ids
    /// @param gooTokens - amount of goo to withdraw
    /// @param receiver - address to receive GBR
    /// @return fractions - amount of GBR minted
    function deposit(uint256[] calldata gobblers, uint256 gooTokens, address receiver)
        external
        nonReentrant
        returns (uint256 fractions)
    {
        // Get reserve balances before they are updated from deposit transfers
        (uint112 _gooReserve, uint112 _gobblerReserveMult,) = getReserves(); // gas savings

        // Asses performance fee since last transaction
        _performanceFee(_gooReserve, _gobblerReserveMult);

        // Transfer goo if any
        if (gooTokens > 0) {
            goo.safeTransferFrom(msg.sender, address(this), gooTokens);
            artGobblers.addGoo(gooTokens);
        }

        // Transfer gobblers if any
        for (uint256 i = 0; i < gobblers.length; i++) {
            artGobblers.safeTransferFrom(msg.sender, address(this), gobblers[i]);
        }

        // Get the new reserves after transfers in
        (uint112 _gooBalance, uint112 _gobblerBalanceMult,) = getReserves();
        {
            // Calculate the increase in multiplier
            uint256 gobblerAmountMult = _gobblerBalanceMult - _gobblerReserveMult;

            // Check the total token supply
            uint256 _totalSupply = totalSupply;

            if (_totalSupply == 0) {
                fractions = FixedPointMathLib.sqrt(gooTokens * gobblerAmountMult) - MINIMUM_LIQUIDITY;
                _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
            } else {
                uint256 _kLast = FixedPointMathLib.sqrt(_gooReserve * _gobblerReserveMult);
                uint256 _k = FixedPointMathLib.sqrt(_gooBalance * _gobblerBalanceMult);
                uint256 _deltaK = FixedPointMathLib.divWadDown(_k - _kLast, _kLast);
                fractions = FixedPointMathLib.mulWadDown(_totalSupply, _deltaK);
            }
            require(fractions > 0, "Goober: INSUFFICIENT_LIQUIDITY_MINTED");
        }

        // Mint shares to depositor less management fee
        fractions -= _managementFee(fractions);
        _mint(receiver, fractions);

        // Update kLast and accumulators
        _update(_gooBalance, _gobblerBalanceMult, _gooReserve, _gobblerReserveMult, false);

        emit Deposit(msg.sender, receiver, gobblers, gooTokens, fractions);
    }

    /// @notice Withdraws the requested gobblers and goo tokens from the vault.
    /// @param gobblers - array of gobbler ids
    /// @param gooTokens - amount of goo to withdraw
    /// @param receiver - address to receive the goo and gobblers
    /// @param owner - owner of the shares to be withdrawn
    /// @return fractions - amount of shares that have been withdrawn
    function withdraw(uint256[] calldata gobblers, uint256 gooTokens, address receiver, address owner)
        external
        nonReentrant
        returns (uint256 fractions)
    {
        // Get starting reserves
        (uint112 _gooReserve, uint112 _gobblerReserveMult,) = getReserves();
        (uint112 _gooBalance, uint112 _gobblerBalanceMult) = (_gooReserve, _gobblerReserveMult);

        // Asses performance fee since last transaction
        _performanceFee(_gooReserve, _gobblerReserveMult);

        // Optimistically transfer goo if any
        if (gooTokens >= 0) {
            artGobblers.removeGoo(gooTokens);
            goo.safeTransfer(receiver, gooTokens);
            _gooBalance -= uint112(gooTokens);
        }

        // Optimistically transfer gobblers if any
        uint256 gobblerMult;
        for (uint256 i = 0; i < gobblers.length; i++) {
            gobblerMult = artGobblers.getGobblerEmissionMultiple(gobblers[i]);
            if (gobblerMult < 6) {
                revert InvalidMultiplier(gobblers[i]);
            }
            artGobblers.transferFrom(address(this), receiver, gobblers[i]);
            _gobblerBalanceMult -= uint112(gobblerMult);
        }

        // Measure change
        uint256 _gobblerAmountMult = _gobblerReserveMult - _gobblerBalanceMult;

        require(_gobblerAmountMult > 0 || gooTokens > 0, "Goober: INSUFFICIENT LIQUIDITY WITHDRAW");

        {
            // Calculate the shares to burn based on the changes in k.
            uint256 _totalSupply = totalSupply;
            uint256 _kLast = FixedPointMathLib.sqrt(_gooReserve * _gobblerReserveMult);
            uint256 _k = FixedPointMathLib.sqrt(_gooBalance * _gobblerBalanceMult);
            // We don't want to allow the pool to be looted/decommed, ever
            require(_k > 0, "Goober: MUST LEAVE LIQUIDITY");
            uint256 _deltaK = FixedPointMathLib.divWadUp(_kLast - _k, _kLast);
            fractions = FixedPointMathLib.mulWadUp(_totalSupply, _deltaK);
        }
        // If we are withdrawing on behalf of someone else, we need to check that they have approved us to do so.
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            // Check that we can withdraw the requested amount of liquidity.
            require(allowed >= fractions, "Goober: INSUFFICIENT_ALLOWANCE");

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - fractions;
        }

        // Burn the shares from owner
        _burn(owner, fractions);

        // update reserves
        _update(_gooBalance, _gobblerBalanceMult, _gooReserve, _gobblerReserveMult, false);

        emit Withdraw(msg.sender, receiver, owner, gobblers, gooTokens, fractions);
    }

    // TODO(Get rid of the struct here if possible by getting clever with the stack)
    /// @notice Swaps supplied gobblers/goo for gobblers/goo in the pool
    function swap(SwapParams calldata parameters) external nonReentrant {
        require(parameters.gooOut > 0 || parameters.gobblersOut.length > 0, "Goober: INSUFFICIENT_OUTPUT_AMOUNT");
        uint112 multOut = 0;
        (uint112 _gooReserve, uint112 _gobblerReserve,) = getReserves(); // gas savings

        {
            require(
                parameters.receiver != address(goo) && parameters.receiver != address(artGobblers), "Goober: INVALID_TO"
            );

            // Transfer out

            // Optimistically transfer goo if any
            if (parameters.gooOut >= 0) {
                artGobblers.removeGoo(parameters.gooOut);
                goo.safeTransfer(parameters.receiver, parameters.gooOut);
            }

            // Optimistically transfer gobblers if any
            if (parameters.gobblersOut.length > 0) {
                for (uint256 i = 0; i < parameters.gobblersOut.length; i++) {
                    multOut += uint112(artGobblers.getGobblerEmissionMultiple(parameters.gobblersOut[i]));
                    artGobblers.transferFrom(address(this), parameters.receiver, parameters.gobblersOut[i]);
                }
            }
        }

        // Flash loan call out
        if (parameters.data.length > 0) IGooberCallee(parameters.receiver).gooberCall(parameters);

        {
            // Transfer in

            // Transfer goo if any
            if (parameters.gooIn > 0) {
                goo.safeTransferFrom(msg.sender, address(this), parameters.gooIn);
                artGobblers.addGoo(parameters.gooIn);
            }

            // Transfer gobblers if any
            for (uint256 i = 0; i < parameters.gobblersIn.length; i++) {
                if (artGobblers.getGobblerEmissionMultiple(parameters.gobblersIn[i]) < 6) {
                    revert InvalidMultiplier(parameters.gobblersIn[i]);
                }
                artGobblers.safeTransferFrom(msg.sender, address(this), parameters.gobblersIn[i]);
            }
        }

        (uint112 _gooBalance, uint112 _gobblerBalance,) = getReserves();

        uint256 amount0In =
            _gooBalance > _gooReserve - parameters.gooOut ? _gooBalance - (_gooReserve - parameters.gooOut) : 0;
        uint256 amount1In =
            _gobblerBalance > _gobblerReserve - multOut ? _gobblerBalance - (_gobblerReserve - multOut) : 0;
        require(amount0In > 0 || amount1In > 0, "Goober: INSUFFICIENT_INPUT_AMOUNT");
        {
            uint256 balance0Adjusted = (_gooBalance * 1000) - (amount0In * 3);
            uint256 balance1Adjusted = (_gobblerBalance * 1000) - (amount1In * 3);
            require((balance0Adjusted * balance1Adjusted) >= ((_gooReserve * _gobblerReserve) * 1000 ** 2), "Goober: K");
        }
        // Asses performance fee on the growth of k.
        _performanceFee(_gooBalance, _gobblerBalance);
        // Update oracle
        _update(_gooBalance, _gobblerBalance, _gooReserve, _gobblerReserve, false);
        emit Swap(msg.sender, parameters.receiver, amount0In, amount1In, parameters.gooOut, multOut);
    }
}
