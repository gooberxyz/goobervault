pragma solidity >=0.8.0;

import "./IERC20Metadata.sol";
import "./IERC721Receiver.sol";

// TODO(IERC20 solmate overrides)
// This should really be IERC20Metadata as well
interface IGoober is IERC721Receiver {
    // Errors
    error gobblerInvalidMultiplier();
    error InvalidNFT();
    error InvalidMultiplier(uint256 gobblerId);

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
        address owner;
        address receiver;
        bytes data;
    }

    // Events

    event Deposit(
        address indexed caller,
        address indexed owner,
        address indexed receiver,
        uint256[] gobblers,
        uint256 gooTokens,
        uint256 shares
    );

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
        address indexed receiver
    );

    event Sync(uint112 gooBalance, uint112 multBalance);

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

    function deposit(uint256[] calldata gobblers, uint256 gooTokens, address owner, address receiver)
        external
        returns (uint256 shares);

    function withdraw(uint256[] calldata gobblers, uint256 gooTokens, address receiver, address owner)
        external
        returns (uint256 shares);

    function swap(SwapParams calldata params) external;
}
