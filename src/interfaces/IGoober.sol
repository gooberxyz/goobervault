// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import "./IERC20Metadata.sol";
import "./IERC721Receiver.sol";

// TODO(IERC20 solmate overrides)
// This should really be IERC20Metadata as well
// So we can get all the natspec
interface IGoober is IERC721Receiver {
    // Errors
    error gobblerInvalidMultiplier();
    error InvalidNFT();
    error InvalidMultiplier(uint256 gobblerId);
    error NoSkim();

    /**
     * @notice The caller doesn't have permission to access that function.
     * @param accessor The requesting address.
     * @param permissioned The address which has the requisite permissions.
     */
    error AccessControlViolation(address accessor, address permissioned);

    /**
     * @notice Invalid fee to address.
     * @param feeTo the feeTo address.
     */
    error InvalidAddress(address feeTo);

    // Structs

    struct SwapParams {
        uint256[] gobblersOut;
        uint256 gooOut;
        uint256[] gobblersIn;
        uint256 gooIn;
        address receiver;
        bytes data;
    }

    // Events

    event Deposit(
        address indexed caller, address indexed receiver, uint256[] gobblers, uint256 gooTokens, uint256 shares
    );

    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256[] gobblers,
        uint256 gooTokens,
        uint256 shares
    );

    event FeesAccrued(address indexed feeTo, uint256 shares, bool performanceFee, uint256 _deltaK);

    event Swap(
        address indexed caller,
        address indexed receiver,
        uint256 gooTokensIn,
        uint256 gobblersMultIn,
        uint256 gooTokensOut,
        uint256 gobblerMultOut
    );

    event Sync(uint112 gooBalance, uint112 multBalance);

    // Functions, Non-Mutating

    function previewDeposit(uint256[] calldata gobblers, uint256 gooTokens) external view returns (uint256 fractions);

    function previewWithdraw(uint256[] calldata gobblers, uint256 gooTokens)
        external
        view
        returns (uint256 fractions);

    function previewSwap(uint256[] calldata gobblersIn, uint256 gooIn, uint256[] calldata gobblersOut, uint256 gooOut)
        external
        view
        returns (uint256 additionalGooRequired);

    // Functions

    /**
     * @notice Updates the address fees can be swept to.
     * @param newFeeTo The new address to which fees will be swept.
     */
    function setFeeTo(address newFeeTo) external;

    /**
     * @notice Updates the address fees can be swept to.
     * @param newMinter The new address to which fees will be swept.
     */
    function setMinter(address newMinter) external;

    function deposit(uint256[] calldata gobblers, uint256 gooTokens, address receiver)
        external
        returns (uint256 shares);

    function withdraw(uint256[] calldata gobblers, uint256 gooTokens, address receiver, address owner)
        external
        returns (uint256 shares);

    function swap(SwapParams calldata params) external;
}
