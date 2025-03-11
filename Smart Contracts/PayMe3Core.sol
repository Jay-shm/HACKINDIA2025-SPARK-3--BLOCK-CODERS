// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PayMe3Core
 * @dev Core contract for PayMe3 payment links on Sahara AI Chain
 */
contract PayMe3Core is ReentrancyGuard, Ownable {
    // Events
    event PaymentLinkCreated(bytes32 indexed linkId, address indexed merchant, uint256 amount, address currency);
    event PaymentReceived(bytes32 indexed linkId, address indexed payer, address indexed merchant, uint256 amount, address currency);
    event TokensWhitelisted(address indexed token, bool status);
    event ReceiptGenerated(bytes32 indexed receiptId, bytes32 indexed linkId, address indexed recipient, uint256 timestamp);

    // Struct to store payment link details
    struct PaymentLink {
        address merchant;
        uint256 amount;
        address currency; // Address of the token/currency (address(0) for native token)
        bool isActive;
        string metadata; // Optional metadata (e.g., description, invoice number)
    }

    // Mapping from linkId to PaymentLink
    mapping(bytes32 => PaymentLink) public paymentLinks;
    
    // Whitelist of supported tokens
    mapping(address => bool) public supportedTokens;

    // Platform fee percentage (in basis points, e.g., 50 = 0.5%)
    uint256 public platformFeeRate = 50; // 0.5% default fee
    address public feeCollector;
    
    // Your custom token on Sahara AI Chain
    address public constant CUSTOM_TOKEN_ADDRESS = 0x54062400993995C9ea3fb272C5DFcC62575BE371;
    
    // Add a mapping to store receipt information
    mapping(bytes32 => bool) public receipts;

    constructor() Ownable(msg.sender) {
        feeCollector = msg.sender;
        // Add native token support by default
        supportedTokens[address(0)] = true;
        // Add your custom token support
        supportedTokens[CUSTOM_TOKEN_ADDRESS] = true;
    }

    /**
     * @dev Creates a new payment link
     * @param _amount Amount to be paid
     * @param _currency Address of the token/currency (address(0) for native token)
     * @param _metadata Optional metadata for the payment
     * @return linkId Unique identifier for the payment link
     */
    function createPaymentLink(
        uint256 _amount,
        address _currency,
        string calldata _metadata
    ) external returns (bytes32 linkId) {
        require(_amount > 0, "Amount must be greater than 0");
        require(supportedTokens[_currency], "Currency not supported");

        // Generate unique link ID using merchant address, amount and timestamp
        linkId = keccak256(abi.encodePacked(
            msg.sender, 
            _amount, 
            _currency, 
            block.timestamp, 
            _metadata
        ));

        // Ensure linkId is unique
        require(paymentLinks[linkId].merchant == address(0), "Link ID already exists");

        // Store payment link details
        paymentLinks[linkId] = PaymentLink({
            merchant: msg.sender,
            amount: _amount,
            currency: _currency,
            isActive: true,
            metadata: _metadata
        });

        emit PaymentLinkCreated(linkId, msg.sender, _amount, _currency);
        return linkId;
    }

    /**
     * @dev Process a payment for a specific link
     * @param _linkId The unique identifier for the payment link
     */
    function processPayment(bytes32 _linkId) external payable nonReentrant {
        PaymentLink storage link = paymentLinks[_linkId];
        
        require(link.merchant != address(0), "Invalid payment link");
        require(link.isActive, "Payment link is not active");
        
        if (link.currency == address(0)) {
            // Native token payment
            require(msg.value == link.amount, "Incorrect payment amount");
            
            // Calculate platform fee
            uint256 fee = (link.amount * platformFeeRate) / 10000;
            uint256 merchantAmount = link.amount - fee;
            
            // Transfer to merchant and fee collector
            (bool sentMerchant, ) = link.merchant.call{value: merchantAmount}("");
            require(sentMerchant, "Failed to send to merchant");
            
            (bool sentFee, ) = feeCollector.call{value: fee}("");
            require(sentFee, "Failed to send fee");
        } else {
            // ERC20 token payment
            require(msg.value == 0, "Native token not accepted for token payments");
            IERC20 token = IERC20(link.currency);
            
            // Transfer token from sender to this contract
            require(token.transferFrom(msg.sender, address(this), link.amount), "Token transfer failed");
            
            // Calculate platform fee
            uint256 fee = (link.amount * platformFeeRate) / 10000;
            uint256 merchantAmount = link.amount - fee;
            
            // Transfer tokens to merchant and fee collector
            require(token.transfer(link.merchant, merchantAmount), "Transfer to merchant failed");
            require(token.transfer(feeCollector, fee), "Transfer of fee failed");
        }
        
        // Mark payment link as inactive (one-time use)
        link.isActive = false;
        
        emit PaymentReceived(_linkId, msg.sender, link.merchant, link.amount, link.currency);
    }

    /**
     * @dev Deactivate a payment link (only merchant can deactivate)
     * @param _linkId The unique identifier for the payment link
     */
    function deactivatePaymentLink(bytes32 _linkId) external {
        PaymentLink storage link = paymentLinks[_linkId];
        require(link.merchant == msg.sender, "Not the merchant");
        link.isActive = false;
    }

    /**
     * @dev Get payment link details
     * @param _linkId The unique identifier for the payment link
     */
    function getPaymentLink(bytes32 _linkId) external view returns (
        address merchant,
        uint256 amount,
        address currency,
        bool isActive,
        string memory metadata
    ) {
        PaymentLink storage link = paymentLinks[_linkId];
        return (
            link.merchant,
            link.amount,
            link.currency,
            link.isActive,
            link.metadata
        );
    }

    /**
     * @dev Generate a receipt for a payment link
     * @param _linkId The unique identifier for the payment link
     * @return receiptId Unique identifier for the receipt
     */
    function generateReceipt(bytes32 _linkId) external returns (bytes32 receiptId) {
        PaymentLink storage link = paymentLinks[_linkId];
        require(link.merchant != address(0), "Invalid payment link");
        
        // Generate unique receipt ID
        receiptId = keccak256(abi.encodePacked(_linkId, block.timestamp, msg.sender));
        
        // Store receipt information
        receipts[receiptId] = true;
        
        // Emit receipt event
        emit ReceiptGenerated(receiptId, _linkId, msg.sender, block.timestamp);
        
        return receiptId;
    }

    /**
     * @dev Verify if a receipt ID is valid
     * @param _receiptId The receipt ID to verify
     * @return valid Whether the receipt ID is valid
     */
    function verifyReceipt(bytes32 _receiptId) external view returns (bool valid) {
        return receipts[_receiptId];
    }

    /**
     * @dev Add or remove a token from the supported list (owner only)
     * @param _token Token address
     * @param _isSupported Whether the token should be supported
     */
    function setTokenSupport(address _token, bool _isSupported) external onlyOwner {
        supportedTokens[_token] = _isSupported;
        emit TokensWhitelisted(_token, _isSupported);
    }

    /**
     * @dev Update platform fee rate (owner only)
     * @param _newFeeRate New fee rate in basis points (e.g., 50 = 0.5%)
     */
    function updatePlatformFee(uint256 _newFeeRate) external onlyOwner {
        require(_newFeeRate <= 500, "Fee too high"); // Max 5%
        platformFeeRate = _newFeeRate;
    }

    /**
     * @dev Update fee collector address (owner only)
     * @param _newFeeCollector New fee collector address
     */
    function updateFeeCollector(address _newFeeCollector) external onlyOwner {
        require(_newFeeCollector != address(0), "Invalid address");
        feeCollector = _newFeeCollector;
    }
    
    // Function to receive native tokens
    receive() external payable {}
}