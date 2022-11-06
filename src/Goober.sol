// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";
import "art-gobblers/Goo.sol";
import "art-gobblers/ArtGobblers.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import "./ERC20Upgradable.sol";

contract Goober is
    UUPSUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC20Upgradable
{
    using SafeTransferLib for Goo;
    using FixedPointMathLib for uint256;

    // Constant/Immutable storage

    // TODO(Add casing for gorli deploy)
    Goo public constant goo = Goo(0x600000000a36F3cD48407e35eB7C5c910dc1f7a8);
    ArtGobblers public constant artGobblers = ArtGobblers(0x60bb1e2AA1c9ACAfB4d34F71585D7e959f387769);

    // Mutable storage

    // Multiple of gobbers
    uint256 m = 0;
    //artGobblers.gooBalance(address(this))
    // Last block timestamp
    uint40  private blockTimestampLast; // uses single storage slot, accessible via getReserves
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
        totalGobblerMultiplier += gobMult;
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
        (uint112 gooReserves, uint112 gobblerReserves,) = getReserves();

        // If we are withdrawing on behalf of someone else, we need to check that they have approved us to do so.
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        // Update the global multiplier based on each gobbler we are withdrawing
        for (uint256 i = 0; i < gobblers.length; i++) {
            m -= artGobblers.getGobblerEmissionMultiple(gobblers[i]);
        }

        // Determine how many shares to withdraw
        shares = previewWithdraw(gobblers, gooTokens); // No need to check for rounding error, previewWithdraw rounds up.

        // Check that we can withdraw the requested amount of liquidity.
        require(allowed >= shares, "Goober: INSUFFICIENT_ALLOWANCE");

        transferFrom(owner, receiver, shares);

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

        uint256 gobblerMultBalance = totalGobblerMultiplier;
        uint256 gooBalance = artGobblers.gooBalance(address(this));

        // update reserves
        _update(gooBalance, gobblerMultBalance, gooReserves, gobblerReserves);

        // update kLast
        kLast = uint112(artGobblers.gooBalance(address(this))) * uint112(artGobblers.getUserEmissionMultiple(address(this)));

        // Update latest timestamp
        blockTimestampLast = uint40(block.timestamp);

        emit Withdraw(msg.sender, receiver, owner, gobblers, gooTokens, shares);
    }

    function totalAssets() public view returns (uint256 gobberBal, uint256 gobblerMult, uint256 gooTokens) {
        return (
            artGobblers.balanceOf(address(this)),
            m,
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

    function maxDeposit(address) public pure returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     */
    uint256[50] private __gap;
}
