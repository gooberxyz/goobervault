// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";
import "openzeppelin-contracts/token/ERC721/IERC721Receiver.sol";
import "art-gobblers/Goo.sol";
import "art-gobblers/ArtGobblers.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import "./math/UQ112x112.sol";
import "./interfaces/IGooberCallee.sol";
import "./ERC20Upgradable.sol";

contract Goober is
    UUPSUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC20Upgradable,
    IERC721Receiver
{
    using SafeTransferLib for Goo;
    using FixedPointMathLib for uint256;
    using UQ112x112 for uint224;

    error InvalidNFT();
    error InvalidMultiplier(uint256 gobblerId);

    // Constant/Immutable storage

    // TODO(Add casing for gorli deploy)
    Goo public constant goo = Goo(0x600000000a36F3cD48407e35eB7C5c910dc1f7a8);
    ArtGobblers public constant artGobblers = ArtGobblers(0x60bb1e2AA1c9ACAfB4d34F71585D7e959f387769);

    // Mutable storage

    //artGobblers.gooBalance(address(this))
    // Last block timestamp
    uint40 private blockTimestampLast; // uses single storage slot, accessible via getReserves
    // Accumulators
    uint256 public priceGooCumulativeLast;
    uint256 public priceGobblerCumulativeLast;
    uint256 public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    // EVENTS

    event Deposit(address indexed caller, address indexed owner, uint256[] gobblers, uint256 gooTokens, uint256 shares);

    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256[] gobblers,
        uint256 gooTokens,
        uint256 shares
    );

    event Swap(
        address indexed sender,
        uint256 gooTokensIn,
        uint256 gobblersMultIn,
        uint256 gooTokensOut,
        uint256 gobblerMultOut,
        address indexed to
    );

    event Sync(uint112 gooBalance, uint112 multBalance);

    // Constructor/init

    constructor() initializer {}

    function initialize() public initializer {
        // @dev as there is no constructor, we need to initialise the these explicitly
        __UUPSUpgradeable_init();
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __ERC20_init("Goober", "GBR");
    }

    // @dev required by the UUPS module
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // update reserves and, on the first call per block, price accumulators
    function _update(uint256 gooBalance, uint256 gobblerBalance, uint112 _gooReserve, uint112 _gobblerReserve)
        private
    {
        require(gooBalance <= type(uint112).max && gobblerBalance <= type(uint112).max, "Goober: OVERFLOW");
        uint40 blockTimestamp = uint40(block.timestamp % 2 ** 40);
        uint40 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _gooReserve != 0 && _gobblerReserve != 0) {
            // * never overflows, and + overflow is desired
            priceGooCumulativeLast += uint256(UQ112x112.encode(_gobblerReserve).uqdiv(_gooReserve)) * timeElapsed;
            priceGobblerCumulativeLast += uint256(UQ112x112.encode(_gooReserve).uqdiv(_gobblerReserve)) * timeElapsed;
        }
        // TODO(Do we need any special magic here)
        //reserve0 = uint112(gooBalance);
        //reserve1 = uint112(gobblerBalance);
        blockTimestampLast = blockTimestamp;
        emit Sync(uint112(gooBalance), uint112(gobblerBalance));
    }

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

    // G can be derived from Goo.totalSupply, plus the issuance rate
    // M we can track internally
    // B
    // Q must be tracked via an off chain oracle

    // When our GOO balance exceeds M/Q * G at time t where M is the total multiple of our GOBBLER and Q is the
    // total multiple of all GOBBLER and G is the total supply of GOO we have too much goo in the tank.

    // When our GOO balance is less than M/Q * G at time t where M is the total multiple of our GOBBLER and Q is
    // the total multiple of all GOBBLER and G is the total supply of GOO we have too little goo in the tank.

    // When our GOO balance equals M/Q * G at time t where M is the total multiple of our GOBBLER and Q is the
    // total multiple of all GOBBLER and G is the total supply of GOO we have the right amount in the tank.

    // And, the events that can push us out of bounds are the deposit or withdraw of GOO/GOBBLER from
    // the vault, mint of new GOBBLER (changes Q) or burn of gobblers from minting of legendary

    // TODO(Pages)
    // TODO(Legendary gobblers)

    // Users need to be able to deposit and withdraw goo or gobblers
    // Gobblers are valued by mult

    function deposit(uint256[] calldata gobblers, uint256 gooTokens, address receiver)
        public
        returns (uint256 shares)
    {
        shares = previewDeposit(gobblers, gooTokens);
        // Check for rounding error since we round down in previewDeposit.
        require(shares != 0, "ZERO_SHARES");

        // Need to transfer before minting or ERC777s could reenter.
        // Transfer goo if any
        if (gooTokens >= 0) {
            goo.safeTransferFrom(msg.sender, address(this), gooTokens);
            artGobblers.addGoo(gooTokens);
        }

        // Transfer gobblers if any
        for (uint256 i = 0; i < gobblers.length; i++) {
            artGobblers.safeTransferFrom(msg.sender, address(this), gobblers[i]);
        }

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, gobblers, gooTokens, shares);
    }

    function withdraw(uint256[] calldata gobblers, uint256 gooTokens, address receiver, address owner)
        public
        virtual
        returns (uint256 shares)
    {
        shares = previewWithdraw(gobblers, gooTokens); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, gobblers, gooTokens, shares);

        // Transfer goo if any
        if (gooTokens >= 0) {
            artGobblers.removeGoo(gooTokens);
            goo.safeTransfer(receiver, gooTokens);
        }

        // Transfer gobblers if any
        for (uint256 i = 0; i < gobblers.length; i++) {
            artGobblers.safeTransferFrom(address(this), receiver, gobblers[i]);
        }
    }

    function totalAssets() public view returns (uint256 gobblerBal, uint256 gobblerMult, uint256 gooTokens) {
        gobblerBal = artGobblers.balanceOf(address(this));
        gobblerMult = artGobblers.getUserEmissionMultiple(address(this));
        gooTokens = goo.balanceOf(address(this)) + artGobblers.gooBalance(address(this));
    }

    // TODO(Views for goo and gobbler exchange rates to GBR)

    function previewDeposit(uint256[] calldata gobblers, uint256 gooTokens) public view returns (uint256 shares) {
        return 1;
    }

    function previewWithdraw(uint256[] calldata gobblers, uint256 gooTokens) public view returns (uint256 shares) {
        return 1;
    }

    function maxDeposit(address) public pure returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view returns (uint256) {
        return type(uint256).max;
    }

    // TODO(u256?)
    function getReserves()
        public
        view
        returns (uint112 _gooReserve, uint112 _gobblerReserve, uint40 _blockTimestampLast)
    {
        _gooReserve = uint112(artGobblers.gooBalance(address(this)));
        _gobblerReserve = uint112(artGobblers.getUserEmissionMultiple(address(this))) * 1000;
        _blockTimestampLast = blockTimestampLast;
    }

    // this low-level function should be called from a contract which performs important safety checks
    function swap(uint256[] calldata gobblers, uint256 gooTokens, address to, bytes calldata data)
        external
        nonReentrant
    {
        uint40 multOut = 0;
        // Sum the multipliers of requested gobblers
        {
            if (gobblers.length > 0) {
                uint40 gobMult;
                for (uint256 i = 0; i < gobblers.length; i++) {
                    gobMult = uint40(artGobblers.getGobblerEmissionMultiple(i));
                    if (gobMult < 6 || gobMult > 9) {
                        revert InvalidMultiplier(i);
                    }
                    multOut += gobMult;
                }
            }
            require(gooTokens > 0 || multOut > 0, "Goober: INSUFFICIENT_OUTPUT_AMOUNT");
        }
        (uint112 _gooReserve, uint112 _gobblerReserve,) = getReserves(); // gas savings
        require(gooTokens < _gooReserve && multOut < _gobblerReserve, "Goober: INSUFFICIENT_LIQUIDITY");
        uint256 gooBalance;
        uint256 gobblerBalance;
        {
            require(to != address(goo) && to != address(artGobblers), "Goober: INVALID_TO");
            // Optimistically transfer goo if any
            if (gooTokens >= 0) {
                artGobblers.removeGoo(gooTokens);
                goo.safeTransfer(to, gooTokens);
            }

            // Optimistically transfer gobblers if any
            if (gobblers.length > 0) {
                for (uint256 i = 0; i < gobblers.length; i++) {
                    artGobblers.safeTransferFrom(address(this), to, gobblers[i]);
                }
            }

            // Flash swap
            if (data.length > 0) IGooberCallee(to).gooberCall(msg.sender, gobblers, gooTokens, data);

            // This goo isn't yet deposited
            gooBalance = goo.balanceOf(address(this));
            // Deposit goo to tank
            artGobblers.addGoo(gooBalance);

            // We have an updated multiplier from safe transfer callbacks
            gobblerBalance = artGobblers.getUserEmissionMultiple(address(this));
        }
        uint256 amount0In = gooBalance > _gooReserve - gooTokens ? gooBalance - (_gooReserve - gooTokens) : 0;
        uint256 amount1In =
            gobblerBalance > _gobblerReserve - multOut ? gobblerBalance - (_gobblerReserve - multOut) : 0;
        require(amount0In > 0 || amount1In > 0, "Goober: INSUFFICIENT_INPUT_AMOUNT");
        {
            // scope for reserve{0,1}Adjusted, avoids stack too deep errors
            // TODO(Test and figure this bit out)
            // We can only feasibly charge fees on goo
            uint256 balance0Adjusted = (gooBalance * 1000) - (amount0In * 3);
            //uint256 balance1Adjusted = (gobblerBalance * 1000) - (amount1In * 3);
            require(
                (balance0Adjusted * gobblerBalance) >= (uint256(_gooReserve) * _gobblerReserve * 1000 ** 2), "Goober: K"
            );
        }
        _update(gooBalance, gobblerBalance, _gooReserve, _gobblerReserve);
        emit Swap(msg.sender, amount0In, amount1In, gooTokens, multOut, to);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function mint(uint depositGoo, uint256[] calldata gobblerTokenIdBatch) external nonReentrant returns (uint liquidity) {
        goo.transferFrom(msg.sender, address(this), depositGoo);
        getGobblerTokensWithSumMultiplier(gobblerTokenIdBatch);
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        uint balance0 = artGobblers.getUserEmissionMultiple(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        uint amount0 = balance0.sub(_reserve0);
        uint amount1 = balance1.sub(_reserve1);

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0.mul(amount1)).sub(MINIMUM_LIQUIDITY);
           _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = Math.min(amount0.mul(_totalSupply) / _reserve0, amount1.mul(_totalSupply) / _reserve1);
        }
        require(liquidity > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED');
        _mint(msg.sender, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);
    }

    function getGobblerTokensWithSumMultiplier(uint256[] calldata gobblerTokenIdBatch) public returns (uint gobblerBatchMultiplierSum) {
        for(uint i = 0; i <= gobblerTokenIdBatch.length ;i++){
          uint currentGobblerMultiplier = artGobblers.getGobblerEmissionMultiple(gobblerTokenIdBatch[i]);
          if(currentGobblerMultiplier < 6 || 9 < currentGobblerMultiplier){ revert gobblerInvalidMultiplier(); }
            artGobblers.safeTransferFrom(msg.sender,address(this),gobblerTokenIdBatch[i]);
            gobblerBatchMultiplierSum = gobblerBatchMultiplierSum + currentGobblerMultiplier;
        }
        return gobblerBatchMultiplierSum;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     */
    uint256[50] private __gap;
}
