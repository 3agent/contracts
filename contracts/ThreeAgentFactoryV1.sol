// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./CurvedToken.sol";
import "./BondingCurve.sol";

/**
 * @title ThreeAgentFactoryV1
 * @notice Factory contract for creating token and bonding curve pairs
 * @dev Uses UUPS proxy pattern for upgradeability and includes reentrancy protection
 */
contract ThreeAgentFactoryV1 is Initializable, OwnableUpgradeable, ReentrancyGuard {
    /**
     * @dev Struct to store deployment information
     * @param token Address of the deployed token contract
     * @param curve Address of the deployed bonding curve contract
     * @param creator Address that initiated the deployment
     * @param timestamp When the deployment occurred
     */
    struct DeploymentInfo {
        address token;
        address curve;
        address creator;
        uint256 timestamp;
    }

    // Array to store all deployments
    DeploymentInfo[] public deployments;

    // Critical addresses for contract operation
    address public wethAddress;
    address public nonfungiblePositionManagerAddress;

    // Protocol fee configuration
    address public protocolFeeRecipient;
    uint256 public protocolFeePercent;

    // Events
    event TokenAndCurveCreated(
        address indexed creator,
        address indexed token,
        address indexed curve,
        uint256 timestamp
    );
    event FeeParametersUpdated(address indexed recipient, uint256 feePercent);
    event WethAddressUpdated(address indexed oldAddress, address indexed newAddress);
    event PositionManagerUpdated(address indexed oldAddress, address indexed newAddress);

    /**
     * @notice Initializes the contract with required parameters
     * @param _wethAddress Address of the WETH contract
     * @param _nonfungiblePositionManagerAddress Address of the position manager
     * @param _protocolFeeRecipient Address to receive protocol fees
     * @param _protocolFeePercent Protocol fee percentage in basis points
     */
    function initialize(
        address _wethAddress,
        address _nonfungiblePositionManagerAddress,
        address _protocolFeeRecipient,
        uint256 _protocolFeePercent
        // TODO: turn back to external
    ) public initializer {
        require(_wethAddress != address(0), "Invalid WETH address");
        require(_nonfungiblePositionManagerAddress != address(0), "Invalid position manager");
        require(_protocolFeeRecipient != address(0), "Invalid fee recipient");

        __Ownable_init(_msgSender());

        wethAddress = _wethAddress;
        nonfungiblePositionManagerAddress = _nonfungiblePositionManagerAddress;
        protocolFeeRecipient = _protocolFeeRecipient;
        protocolFeePercent = _protocolFeePercent;
    }

    /**
     * @notice Creates a new token and bonding curve pair
     * @param name Name of the token
     * @param symbol Symbol of the token
     * @return tokenAddr Address of the created token
     * @return curveAddr Address of the created bonding curve
     */
    function createTokenAndCurve(
        string calldata name,
        string calldata symbol
    ) external virtual nonReentrant returns (address tokenAddr, address curveAddr) {
        require(bytes(name).length > 0 && bytes(name).length <= 32, "Invalid name length");
        require(bytes(symbol).length > 0 && bytes(symbol).length <= 8, "Invalid symbol length");

        // Create bonding curve first with placeholder token address
        BondingCurve curve = new BondingCurve(
            address(0),
            wethAddress,
            nonfungiblePositionManagerAddress,
            protocolFeeRecipient,
            protocolFeePercent,
            address(this)
        );

        // Create token with curve address
        CurvedToken token = new CurvedToken(address(curve), name, symbol);

        // Set token address in curve
        curve.setToken(address(token));

        // Record deployment
        deployments.push(
            DeploymentInfo({
                token: address(token),
                curve: address(curve),
                creator: msg.sender,
                timestamp: block.timestamp
            })
        );

        emit TokenAndCurveCreated(msg.sender, address(token), address(curve), block.timestamp);

        return (address(token), address(curve));
    }

    /**
     * @notice Updates protocol fee parameters
     * @param _protocolFeeRecipient New fee recipient address
     * @param _protocolFeePercent New fee percentage in basis points
     */
    function setProtocolFeeParameters(
        address _protocolFeeRecipient,
        uint256 _protocolFeePercent
    ) external onlyOwner {
        require(_protocolFeeRecipient != address(0), "Invalid fee recipient");

        protocolFeeRecipient = _protocolFeeRecipient;
        protocolFeePercent = _protocolFeePercent;
        
        emit FeeParametersUpdated(_protocolFeeRecipient, _protocolFeePercent);
    }

    /**
     * @notice Updates WETH address
     * @param _newWethAddress New WETH contract address
     */
    function setWethAddress(address _newWethAddress) external onlyOwner {
        require(_newWethAddress != address(0), "Invalid WETH address");
        address oldAddress = wethAddress;
        wethAddress = _newWethAddress;
        emit WethAddressUpdated(oldAddress, _newWethAddress);
    }

    /**
     * @notice Gets deployment information by index
     * @param index Index in the deployments array
     * @return DeploymentInfo struct containing deployment details
     */
    function getDeployment(uint256 index) external view returns (DeploymentInfo memory) {
        require(index < deployments.length, "Invalid index");
        return deployments[index];
    }

    /**
     * @notice Gets the total number of deployments
     * @return Number of deployments
     */
    function getDeploymentsCount() external view returns (uint256) {
        return deployments.length;
    }

    /**
     * @notice Gets the most recent deployment
     * @return DeploymentInfo struct of the latest deployment
     */
    function getLatestDeployment() external view returns (DeploymentInfo memory) {
        require(deployments.length > 0, "No deployments");
        return deployments[deployments.length - 1];
    }
}