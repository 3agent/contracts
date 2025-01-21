// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title CurvedToken
/// @notice An ERC20 token that implements a bonding curve mechanism
/// @dev Only the bonding curve contract can mint and burn tokens
contract CurvedToken is ERC20, ReentrancyGuard {

    address public immutable bondingCurve;
    uint256 public immutable creationTimestamp;
    address public immutable factory;

    // Events
    event Minted(address indexed to, uint256 amount, uint256 totalSupply);
    event Burned(address indexed from, uint256 amount, uint256 totalSupply);

    // Custom errors
    error NotAuthorizedToMint();
    error NotAuthorizedToBurn();
    error InvalidMintAmount();
    error InsufficientBalance();
    error ZeroAmount();
    error ZeroAddressNotAllowed();

    constructor(
        address _bondingCurve,
        string memory name,
        string memory symbol
    ) ERC20(name, symbol) {
        if (_bondingCurve == address(0)) revert ZeroAddressNotAllowed();

        bondingCurve = _bondingCurve;
        factory = msg.sender;
        creationTimestamp = block.timestamp;
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    /// @notice Mints new tokens to the specified address
    /// @param to The address that will receive the minted tokens
    /// @param amount The amount of tokens to mint
    function mint(address to, uint256 amount) external nonReentrant {
        if (msg.sender != bondingCurve) revert NotAuthorizedToMint();
        if (to == address(0)) revert ZeroAddressNotAllowed();
        if (amount == 0) revert ZeroAmount();

        _mint(to, amount);
        emit Minted(to, amount, totalSupply());
    }

    /// @notice Burns tokens from the specified address
    /// @param from The address from which tokens will be burned
    /// @param amount The amount of tokens to burn
    function burn(address from, uint256 amount) external nonReentrant {
        if (msg.sender != bondingCurve) revert NotAuthorizedToBurn();
        if (from == address(0)) revert ZeroAddressNotAllowed();
        if (amount == 0) revert ZeroAmount();
        if (amount > balanceOf(from)) revert InsufficientBalance();

        _burn(from, amount);
        emit Burned(from, amount, totalSupply());
    }
}