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
    bool public switchState = true; 

    function toggleSwitch() public onlyOwner returns (bool status) {
    switchState = !switchState;
    return switchState;
    }

    // Array that keeps track of count of each mult in vault
    // updated by _update(). Useful for later math.
    uint8[] multsCount = new uint8[](5); 

    // Accumulators
    uint256 public priceGooCumulativeLast;
    uint256 public priceGobblerCumulativeLast;

    // reserve0 (gooBalance) * reserve1 (totalGobblerMultiplier), as of immediately after the most recent liquidity event
    uint256 private kLast;

    // Last block timestamp
    uint40 private blockTimestampLast; // uses single storage slot, accessible via getReserves

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
    /// @dev required by the UUPS module
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // update reserves and, on the first call per block, price accumulators
    // TODO: Update the multsCount array. 
    function _update(uint256 gooBalance, uint256 gobblerBalance, uint112 _gooReserve, uint112 _multReserve)
        private
    {
        require(gooBalance <= type(uint112).max && gobblerBalance <= type(uint112).max, "Goober: OVERFLOW");
        uint40 blockTimestamp = uint40(block.timestamp % 2 ** 40);
        uint40 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _gooReserve != 0 && _multReserve != 0) {
            // * never overflows, and + overflow is desired
            priceGooCumulativeLast += uint256(UQ112x112.encode(_multReserve).uqdiv(_gooReserve)) * timeElapsed;
            priceGobblerCumulativeLast += uint256(UQ112x112.encode(_gooReserve).uqdiv(_multReserve)) * timeElapsed;
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

    /// @notice Withdraw shares from the vault
    /// @param gobblers - array of gobbler ids
    /// @param gooTokens - amount of goo to withdraw
    /// @param receiver - address to receive the goo and gobblers
    /// @param owner - owner of the shares to be withdrawn
    /// @return shares - amount of shares that have been withdrawn
    function withdraw(uint256[] calldata gobblers, uint256 gooTokens, address receiver, address owner)
        public
        virtual
        returns (uint256 shares)
    {
        // If we are withdrawing on behalf of someone else, we need to check that they have approved us to do so.
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        // Determine how many shares to withdraw
        shares = previewWithdraw(gobblers, gooTokens); // No need to check for rounding error, previewWithdraw rounds up.

        // Burn the shares
        _burn(owner, shares);

        // Transfer goo if any
        if (gooTokens >= 0) {
            artGobblers.removeGoo(gooTokens);
            goo.safeTransfer(receiver, gooTokens);
        }

        // Transfer gobblers if any
        for (uint256 i = 0; i < gobblers.length; i++) {
            artGobblers.safeTransferFrom(address(this), receiver, gobblers[i]);
        }

        // Update latest timestamp
        blockTimestampLast = uint40(block.timestamp);

        emit Withdraw(msg.sender, receiver, owner, gobblers, gooTokens, shares);
    }

    function totalAssets() public view returns (uint256 gobberBal, uint256 gobblerMult, uint256 gooTokens) {
        return (
            artGobblers.balanceOf(address(this)),
            artGobblers.getUserEmissionMultiple(address(this)),
            goo.balanceOf(address(this)) + artGobblers.gooBalance(address(this))
        );
    }

    // TODO(Views for goo and gobbler exchange rates to GBR)
    function previewDeposit(uint256[] calldata gobblers, uint256 gooTokens) public view returns (uint256 shares) {
        return 1;
    }

    function previewWithdraw(uint256[] calldata gobblers, uint256 gooTokens) public view returns (uint256 shares) {
        return 1;
    }

    // Should return the pool's exchange rate between Goo/Mult. 
    function previewSwap(uint256[] calldata gobblers, uint256 gooTokens) public view returns (uint256 rate) {
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
        returns (uint112 _gooReserve, uint112 _multReserve, uint40 _blockTimestampLast)
    {
        _gooReserve = uint112(artGobblers.gooBalance(address(this)));
        _multReserve = uint112(artGobblers.getUserEmissionMultiple(address(this))) * 1000;
        _blockTimestampLast = blockTimestampLast;
    }

    // TODO(Return the quantity of each mult number held by the pool)
    function getGobblerCount() external view virtual returns (uint256[] memory) {
        return 1;
    }

    // Sells the caller Gobblers in exchange for Goo, slightly
    // below the current auction price (can be determined by curve)
    // if the vault is in mint mode and can afford a Gobbler.
    // TODO(Take into account mint probability as a premium/discount)
    function gobblerOTC(uint256[] calldata gobblers, uint256 gooTokens, address receiver) external nonReentrant
    returns (uint256 profit) {
        // TODO(Add require mintMode == 1)
        (uint112 _gooReserve, uint112 _multReserve,) = getReserves(); // gas savings
        uint40 mintPrice = artGobblers.gobblerPrice();
            require(_gooReserve - 6 >= _multReserve && _gooReserve > mintPrice, 
            "Goober: INSUFFICENT_GOO");
             // Transfer gobblers if any
            for (uint256 i = 0; i < gobblers.length; i++) {
            artGobblers.safeTransferFrom(msg.sender, address(this), gobblers[i]);
            }
            //TODO calculate how much Goo they should get.
    }


    // Will need to call _update() to update reserves of Gobblers and Goo (upon success). 
    // Will need to remove the Goo from the Gobblers (virtual), in order to 
    // either mint a Gobbler by burning Goo, or sell the Goo for Eth and buying a Gobbler
    // off secondary. 
    // TODO Require the switch to be turned ON (1 vs. 0 == OFF). 

    function mintGobbler() public nonReentrant {
            require(switchState, "Goober: INSUFFICENT_GOO");
            (uint112 _gooReserve, uint112 _multReserve,) = getReserves(); // Gas savings
            uint256 gooBalance = goo.balanceOf(address(this));
            uint256 gobblerBalance = artGobblers.getUserEmissionMultiple(address(this));
            uint40 _mintPrice = FixedPointMathLib.mulWadDown(artGobblers.gobblerPrice(), 1);
            uint40 _newGooReserve = FixedPointMathLib.mulWadDown(_gooReserve, 1);
            uint40 _newMultReserve = _multReserve / 1000;
            // Mint Gobblers to pool while we can afford it 
            // and when our Goo per Mult < Auction Goo per Mult.
            // 7.3294 = weighted avg Mult from mint = ((6*3057) + (7*2621) + (8*2293) + (9*2029))/10000.
            while ((_newGooReserve > _mintPrice) && 
                   ((_newGooReserve / _newMultReserve) <= (_mintPrice * 10000) / 73294)) {   
                    artGobblers.mintFromGoo(_mintPrice, true);
                    _mintPrice = artGobblers.gobblerPrice();
                    _update(gooBalance, gobblerBalance, _newGooReserve, _newMultReserve);
                    (_newGooReserve, _newMultReserve,) = getReserves();
                    }
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
        (uint112 _gooReserve, uint112 _multReserve,) = getReserves(); // gas savings
        require(gooTokens < _gooReserve && multOut < _multReserve, "Goober: INSUFFICIENT_LIQUIDITY");
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
            gobblerBalance > _multReserve - multOut ? gobblerBalance - (_multReserve - multOut) : 0;
        require(amount0In > 0 || amount1In > 0, "Goober: INSUFFICIENT_INPUT_AMOUNT");
        {
            // scope for reserve{0,1}Adjusted, avoids stack too deep errors
            // TODO(Test and figure this bit out)
            // We can only feasibly charge fees on goo
            uint256 balance0Adjusted = (gooBalance * 1000) - (amount0In * 3);
            //uint256 balance1Adjusted = (gobblerBalance * 1000) - (amount1In * 3);
            require(
                (balance0Adjusted * gobblerBalance) >= (uint256(_gooReserve) * _multReserve * 1000 ** 2), "Goober: K"
            );
        }
        _update(gooBalance, gobblerBalance, _gooReserve, _multReserve);
        emit Swap(msg.sender, amount0In, amount1In, gooTokens, multOut, to);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     */
    uint256[50] private __gap;

} 