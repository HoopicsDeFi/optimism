// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Predeploys } from "src/libraries/Predeploys.sol";
import { L2StandardBridge } from "src/L2/L2StandardBridge.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IOptimismERC20Factory } from "src/L2/interfaces/IOptimismERC20Factory.sol";

/// @notice Thrown when the decimals of the tokens are not the same.
error InvalidDecimals();

/// @notice Thrown when the legacy address is not found in the OptimismMintableERC20Factory.
error InvalidLegacyERC20Address();

/// @notice Thrown when the SuperchainERC20 address is not found in the SuperchainERC20Factory.
error InvalidSuperchainERC20Address();

/// @notice Thrown when the remote addresses of the tokens are not the same.
error InvalidTokenPair();

/// TODO: Define a better naming convention for this interface.
/// @notice Interface for minting and burning tokens in the L2StandardBridge.
///         Used for StandardL2ERC20, OptimismMintableERC20 and OptimismSuperchainERC20.
interface MintableAndBurnable is IERC20 {
    function mint(address, uint256) external;
    function burn(address, uint256) external;
}

/// @custom:proxied true
/// @custom:predeploy 0x4200000000000000000000000000000000000010
/// @title L2StandardBridgeInterop
/// @notice The L2StandardBridgeInterop is an extension of the L2StandardBridge that allows for
///         the conversion of tokens between legacy tokens (OptimismMintableERC20 or StandardL2ERC20)
///         and SuperchainERC20 tokens.
contract L2StandardBridgeInterop is L2StandardBridge {
    /// @notice Emitted when a conversion is made.
    /// @param from The token being converted from.
    /// @param to The token being converted to.
    /// @param caller The caller of the conversion.
    /// @param amount The amount of tokens being converted.
    event Converted(address indexed from, address indexed to, address indexed caller, uint256 amount);

    /// @notice Semantic version.
    /// @custom:semver +interop
    function version() public pure override returns (string memory) {
        return string.concat(super.version(), "+interop");
    }

    /// @notice Converts `amount` of `from` token to `to` token.
    /// @param _from The token being converted from.
    /// @param _to The token being converted to.
    /// @param _amount The amount of tokens being converted.
    function convert(address _from, address _to, uint256 _amount) external {
        _validatePair(_from, _to);

        MintableAndBurnable(_from).burn(msg.sender, _amount);
        MintableAndBurnable(_to).mint(msg.sender, _amount);

        emit Converted(_from, _to, msg.sender, _amount);
    }

    /// @notice Validates the pair of tokens.
    /// @param _from The token being converted from.
    /// @param _to The token being converted to.
    function _validatePair(address _from, address _to) internal view {
        // 1. Decimals check
        if (IERC20Metadata(_from).decimals() != IERC20Metadata(_to).decimals()) revert InvalidDecimals();

        // Order tokens for factory validation
        if (_isOptimismMintableERC20(_from)) {
            _validateFactories(_from, _to);
        } else {
            _validateFactories(_to, _from);
        }
    }

    /// @notice Validates that the tokens are deployed by the correct factory.
    /// @param _legacyAddr The legacy token address (OptimismMintableERC20 or StandardL2ERC20).
    /// @param _superAddr The SuperchainERC20 address.
    function _validateFactories(address _legacyAddr, address _superAddr) internal view {
        // 2. Valid legacy check
        address _legacyRemoteToken =
            IOptimismERC20Factory(Predeploys.OPTIMISM_MINTABLE_ERC20_FACTORY).deployments(_legacyAddr);
        if (_legacyRemoteToken == address(0)) revert InvalidLegacyERC20Address();

        // 3. Valid SuperchainERC20 check
        address _superRemoteToken =
            IOptimismERC20Factory(Predeploys.OPTIMISM_SUPERCHAIN_ERC20_FACTORY).deployments(_superAddr);
        if (_superRemoteToken == address(0)) revert InvalidSuperchainERC20Address();

        // 4. Same remote address check
        if (_legacyRemoteToken != _superRemoteToken) revert InvalidTokenPair();
    }
}