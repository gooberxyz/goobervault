// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "openzeppelin-contracts/token/ERC721/IERC721Receiver.sol";
import "art-gobblers/Goo.sol";
import "art-gobblers/ArtGobblers.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import "./math/UQ112x112.sol";
import "./interfaces/IGoober.sol";
import "./interfaces/IGooberCallee.sol";

contract Goober is ReentrancyGuard, ERC20, IGoober {
    using SafeTransferLib for Goo;
    using FixedPointMathLib for uint256;
    using UQ112x112 for uint224;

    // Constant/Immutable storage

    // TODO(Optimize storage layout)

    Goo public immutable goo;
    ArtGobblers public immutable artGobblers;

    uint256 private constant MINIMUM_LIQUIDITY = 10 ** 3;
    uint256 private constant MULT_SCALAR = 10 ** 3;

    // Mutable storage

    // Access control
    address feeTo;
    address minter;

    // TODO(Do we need the accumulators for twap?)
    // TODO(Can these be 112?)
    // Accumulators
    uint256 public priceGooCumulativeLast;
    uint256 public priceGobblerCumulativeLast;

    // TODO(Do we have a use case for storing accumulators or kLast anymore?)
    // Likely for calculating performance fees and providing an oracle
    // sqrt(gooBalance * totalGobblerMultiplier), as of immediately after the most recent liquidity event
    uint112 public kLast;

    // Last block timestamp
    uint40 private blockTimestampLast; // uses single storage slot, accessible via getReserves

    // Constructor/init

    constructor(address _gobblersAddress, address _gooAddress, address _feeTo, address _minter)
        ERC20("Goober", "GBR", 18)
    {
        feeTo = _feeTo;
        minter = _minter;
        artGobblers = ArtGobblers(_gobblersAddress);
        goo = Goo(_gooAddress);
    }

    /// @inheritdoc IGoober
    function setFeeTo(address newFeeTo) public {
        if (msg.sender != feeTo) {
            revert AccessControlViolation(msg.sender, feeTo);
        }
        if (newFeeTo == address(0)) {
            revert InvalidAddress(newFeeTo);
        }
        feeTo = newFeeTo;
    }

    /// @inheritdoc IGoober
    function setMinter(address newMinter) public {
        if (msg.sender != feeTo) {
            revert AccessControlViolation(msg.sender, feeTo);
        }
        if (newMinter == address(0)) {
            revert InvalidAddress(newMinter);
        }
        minter = newMinter;
    }

    /// @dev update reserves and, on the first call per block, price accumulators
    /// @param gooBalance the new goo balance
    /// @param gobblerBalance the new gobblers multiplier
    /// @param _gooReserve the current goo reserve
    /// @param _gobblerReserve the current gobblers reserve
    function _update(uint256 gooBalance, uint256 gobblerBalance, uint112 _gooReserve, uint112 _gobblerReserve)
        private
    {
        // Check if the reserves will overflow
        require(gooBalance <= type(uint112).max && gobblerBalance <= type(uint112).max, "Goober: OVERFLOW");

        uint40 blockTimestamp = uint40(block.timestamp % 2 ** 40);

        uint40 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired

        if (timeElapsed > 0 && _gooReserve != 0 && _gobblerReserve != 0) {
            unchecked {
                // * never overflows, and + overflow is desired
                priceGooCumulativeLast += uint256(UQ112x112.encode(_gobblerReserve).uqdiv(_gooReserve)) * timeElapsed;
                priceGobblerCumulativeLast +=
                    uint256(UQ112x112.encode(_gooReserve).uqdiv(_gobblerReserve)) * timeElapsed;
            }
        }
        // TODO(Do we need any special magic here)
        //reserve0 = uint112(gooBalance);
        //reserve1 = uint112(gobblerBalance);
        blockTimestampLast = blockTimestamp;
        emit Sync(uint112(gooBalance), uint112(gobblerBalance));
    }

    /// @inheritdoc IERC721Receiver
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4)
    {
        if (msg.sender != address(artGobblers)) {
            revert InvalidNFT();
        }
        uint40 gobMult = uint40(artGobblers.getGobblerEmissionMultiple(tokenId));
        if (gobMult < 6 || gobMult > 9) {
            revert InvalidMultiplier(tokenId);
        }
        return IERC721Receiver.onERC721Received.selector;
    }

    // TODO(Should we use 256 bit for reserves rather than 112 bit Q maths)

    function deposit(uint256[] calldata gobblers, uint256 gooTokens, address owner, address receiver)
        external
        nonReentrant
        returns (uint256 shares)
    {
        // Get reserve balances before they are updated from deposit transfers
        (uint112 _gooReserve, uint112 _gobblerReserveMult,) = getReserves(); // gas savings

        // Need to transfer before minting or ERC777s could reenter.
        // Transfer goo if any
        if (gooTokens > 0) {
            goo.safeTransferFrom(owner, address(this), gooTokens);
            artGobblers.addGoo(gooTokens);
        }

        // Transfer gobblers if any
        for (uint256 i = 0; i < gobblers.length; i++) {
            artGobblers.safeTransferFrom(owner, address(this), gobblers[i]);
        }

        (uint112 _gooBalance, uint112 _gobblerBalanceMult,) = getReserves();
        {
            uint256 gobblerAmountMult = _gobblerBalanceMult - _gobblerReserveMult;

            // TODO(Deal with fees)
            // bool feeOn = _mintFee(_reserve0, _reserve1);
            uint256 _totalSupply = totalSupply;

            if (_totalSupply == 0) {
                // TODO(Test and optimize locked gobbler)
                shares = FixedPointMathLib.sqrt(gooTokens * gobblerAmountMult) - MINIMUM_LIQUIDITY;
                _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
            } else {
                // k is also the amount of goo produced per day
                uint256 _kLast = FixedPointMathLib.sqrt(_gooReserve * _gobblerReserveMult);
                uint256 _k = FixedPointMathLib.sqrt(_gooBalance * _gobblerBalanceMult);
                uint256 _deltaK = FixedPointMathLib.divWadDown(_k - _kLast, _kLast);
                shares = FixedPointMathLib.mulWadDown(_totalSupply, _deltaK);
            }
            require(shares > 0, "Goober: INSUFFICIENT_LIQUIDITY_MINTED");
            _mint(receiver, shares);
        }

        _update(_gooBalance, _gobblerBalanceMult, _gooReserve, _gobblerReserveMult);

        // TODO(Fee math)
        //if (feeOn) kLast = uint(_gooReserve).mul(_gobblerReserve); // reserve0 and reserve1 are up-to-date

        emit Deposit(msg.sender, owner, receiver, gobblers, gooTokens, shares);
    }

    /// @notice Withdraws the requested gobblers and goo tokens from the vault.
    /// @param gobblers - array of gobbler ids
    /// @param gooTokens - amount of goo to withdraw
    /// @param receiver - address to receive the goo and gobblers
    /// @param owner - owner of the shares to be withdrawn
    /// @return shares - amount of shares that have been withdrawn
    function withdraw(uint256[] calldata gobblers, uint256 gooTokens, address receiver, address owner)
        external
        nonReentrant
        returns (uint256 shares)
    {
        (uint112 _gooReserve, uint112 _gobblerReserveMult,) = getReserves();

        // Optimistically transfer goo if any
        if (gooTokens >= 0) {
            artGobblers.removeGoo(gooTokens);
            goo.safeTransfer(receiver, gooTokens);
        }

        // Optimistically transfer gobblers if any
        if (gobblers.length > 0) {
            for (uint256 i = 0; i < gobblers.length; i++) {
                artGobblers.transferFrom(address(this), receiver, gobblers[i]);
            }
        }

        (uint112 _gooBalance, uint112 _gobblerBalanceMult,) = getReserves();
        uint256 _gobblerAmountMult = _gobblerReserveMult - _gobblerBalanceMult;

        require(_gobblerAmountMult > 0 && gooTokens > 0, "Goober: INSUFFICIENT LIQUIDITY WITHDRAW");

        {
            uint256 _totalSupply = totalSupply;
            // TODO(Handle fee)
            // bool feeOn = _mintFee(_reserve0, _reserve1);
            uint256 _kLast = FixedPointMathLib.sqrt(_gooReserve * _gobblerReserveMult);
            uint256 _k = FixedPointMathLib.sqrt(_gooBalance * _gobblerBalanceMult);
            // We don't want to allow the pool to be looted/decommed, ever
            require(_k > 0, "Goober: MUST LEAVE LIQUIDITY");
            uint256 _deltaK = FixedPointMathLib.divWadUp(_kLast - _k, _k);
            shares = FixedPointMathLib.mulWadUp(_totalSupply, _deltaK);
        }
        // If we are withdrawing on behalf of someone else, we need to check that they have approved us to do so.
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            // Check that we can withdraw the requested amount of liquidity.
            require(allowed >= shares, "Goober: INSUFFICIENT_ALLOWANCE");

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        // Burn the shares
        _burn(owner, shares);

        // update reserves
        _update(_gooBalance, _gobblerBalanceMult, _gooReserve, _gobblerReserveMult);

        emit Withdraw(msg.sender, receiver, owner, gobblers, gooTokens, shares);
    }

    function totalAssets() public view returns (uint256 gobblerBal, uint256 gobblerMult, uint256 gooTokens) {
        gobblerBal = artGobblers.balanceOf(address(this));
        gobblerMult = artGobblers.getUserEmissionMultiple(address(this));
        gooTokens = goo.balanceOf(address(this)) + artGobblers.gooBalance(address(this));
    }

    function _getScaledAccountMultiple() internal view returns (uint112 multiple) {
        multiple = uint112(artGobblers.getUserEmissionMultiple(address(this)) * MULT_SCALAR);
    }

    function _getScaledTokenMultiple(uint256 gobblerId) internal view returns (uint112 multiple) {
        multiple = uint112(artGobblers.getGobblerEmissionMultiple(gobblerId) * MULT_SCALAR);
    }

    function getReserves()
        public
        view
        returns (uint112 _gooReserve, uint112 _gobblerReserve, uint40 _blockTimestampLast)
    {
        _gooReserve = uint112(artGobblers.gooBalance(address(this)));
        _gobblerReserve = _getScaledAccountMultiple();
        _blockTimestampLast = blockTimestampLast;
    }

    // this low-level function should be called from a contract which performs important safety checks
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
                    multOut += _getScaledTokenMultiple(parameters.gobblersOut[i]);
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
                goo.safeTransferFrom(parameters.owner, address(this), parameters.gooIn);
                artGobblers.addGoo(parameters.gooIn);
            }

            // Transfer gobblers if any
            for (uint256 i = 0; i < parameters.gobblersIn.length; i++) {
                artGobblers.safeTransferFrom(parameters.owner, address(this), parameters.gobblersIn[i]);
            }
        }

        (uint112 _gooBalance, uint112 _gobblerBalance,) = getReserves();

        uint256 amount0In =
            _gooBalance > _gooReserve - parameters.gooOut ? _gooBalance - (_gooReserve - parameters.gooOut) : 0;
        uint256 amount1In =
            _gobblerBalance > _gobblerReserve - multOut ? _gobblerBalance - (_gobblerReserve - multOut) : 0;
        require(amount0In > 0 || amount1In > 0, "Goober: INSUFFICIENT_INPUT_AMOUNT");
        {
            // scope for reserve{0,1}Adjusted, avoids stack too deep errors
            // TODO(Test and figure this bit out)
            // We can only feasibly charge fees on goo
            uint256 balance0Adjusted = (_gooBalance * 1000) - (amount0In * 3);
            uint256 balance1Adjusted = (_gobblerBalance * 1000) - (amount1In * 3);
            require((balance0Adjusted * balance1Adjusted) >= ((_gooReserve * _gobblerReserve) * 1000 ** 2), "Goober: K");
        }
        _update(_gooBalance, _gobblerBalance, _gooReserve, _gobblerReserve);
        emit Swap(msg.sender, amount0In, amount1In, parameters.gooOut, multOut, parameters.receiver);
    }
}
