// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PayMe3Escrow
 * @dev Escrow contract for PayMe3 payment links on Ethereum Sepolia
 */
contract PayMe3Escrow is ReentrancyGuard, Ownable {
    // Enums
    enum EscrowState { Created, Funded, Completed, Refunded, Disputed, Resolved }
    
    // Events
    event EscrowCreated(bytes32 indexed escrowId, address indexed merchant, uint256 amount, address currency);
    event EscrowFunded(bytes32 indexed escrowId, address indexed funder);
    event EscrowCompleted(bytes32 indexed escrowId);
    event EscrowRefunded(bytes32 indexed escrowId);
    event DisputeRaised(bytes32 indexed escrowId, string reason);
    event DisputeResolved(bytes32 indexed escrowId, address winner, uint256 merchantAmount, uint256 buyerAmount);
    event ReceiptGenerated(bytes32 indexed receiptId, bytes32 indexed escrowId, address indexed recipient, uint256 timestamp);
    event TokensWhitelisted(address indexed token, bool status);
    event ArbitratorChanged(address indexed oldArbitrator, address indexed newArbitrator);
    
    // Struct to store escrow details
    struct Escrow {
        address payable merchant;
        address payable buyer;
        uint256 amount;
        address currency; // Address of the token/currency (address(0) for ETH)
        EscrowState state;
        uint256 deadline;
        string description;
        string disputeReason;
    }
    
    // Mapping from escrowId to Escrow
    mapping(bytes32 => Escrow) public escrows;
    
    // Whitelist of supported tokens
    mapping(address => bool) public supportedTokens;
    
    // Receipt mapping
    mapping(bytes32 => bool) public receipts;
    
    // USDT on Sepolia testnet (Note: This is a placeholder - use the actual address)
    address public constant TEST_USDT_ADDRESS = 0x7169D38820dfd117C3FA1f22a697dBA58d90BA06; // Example - replace with actual
    
    // Address of the arbitrator
    address public arbitrator;
    
    // Platform fee percentage (in basis points, e.g., 100 = 1%)
    uint256 public platformFeeRate = 100; // 1% default fee
    address public feeCollector;
    
    // Default escrow time (in days)
    uint256 public defaultEscrowDays = 14;
    
    // Modifiers
    modifier onlyArbitrator() {
        require(msg.sender == arbitrator, "Only arbitrator can call this function");
        _;
    }
    
    modifier validEscrow(bytes32 _escrowId) {
        require(escrows[_escrowId].merchant != address(0), "Escrow does not exist");
        _;
    }
    
    constructor(address _arbitrator) Ownable(msg.sender) {
        arbitrator = _arbitrator;
        feeCollector = msg.sender;
        
        // Add ETH support by default
        supportedTokens[address(0)] = true;
        // Add USDT support
        supportedTokens[TEST_USDT_ADDRESS] = true;
    }
    
    /**
     * @dev Creates a new escrow agreement
     * @param _merchant Address of the merchant/seller
     * @param _amount Amount to be escrowed
     * @param _currency Address of the token/currency (address(0) for ETH)
     * @param _description Description of the escrow agreement
     * @param _deadlineDays Number of days until the escrow expires (0 for default)
     * @return escrowId Unique identifier for the escrow
     */
    function createEscrow(
        address payable _merchant,
        uint256 _amount,
        address _currency,
        string calldata _description,
        uint256 _deadlineDays
    ) external returns (bytes32 escrowId) {
        require(_amount > 0, "Amount must be greater than 0");
        require(_merchant != address(0), "Invalid merchant address");
        require(supportedTokens[_currency], "Currency not supported");
        
        uint256 deadlineDays = _deadlineDays > 0 ? _deadlineDays : defaultEscrowDays;
        uint256 deadline = block.timestamp + (deadlineDays * 1 days);
        
        // Generate unique escrow ID
        escrowId = keccak256(abi.encodePacked(
            msg.sender,
            _merchant,
            _amount,
            _currency,
            block.timestamp,
            _description
        ));
        
        // Ensure escrowId is unique
        require(escrows[escrowId].merchant == address(0), "Escrow ID already exists");
        
        // Store escrow details
        escrows[escrowId] = Escrow({
            merchant: _merchant,
            buyer: payable(msg.sender),
            amount: _amount,
            currency: _currency,
            state: EscrowState.Created,
            deadline: deadline,
            description: _description,
            disputeReason: ""
        });
        
        emit EscrowCreated(escrowId, _merchant, _amount, _currency);
        return escrowId;
    }
    
    /**
     * @dev Fund an existing escrow with payment
     * @param _escrowId The unique identifier for the escrow
     */
    function fundEscrow(bytes32 _escrowId) external payable nonReentrant validEscrow(_escrowId) {
        Escrow storage escrow = escrows[_escrowId];
        
        require(msg.sender == escrow.buyer, "Only buyer can fund the escrow");
        require(escrow.state == EscrowState.Created, "Escrow is not in Created state");
        require(block.timestamp < escrow.deadline, "Escrow deadline has passed");
        
        if (escrow.currency == address(0)) {
            // ETH payment
            require(msg.value == escrow.amount, "Incorrect payment amount");
        } else {
            // ERC20 token payment
            require(msg.value == 0, "ETH not accepted for token escrows");
            IERC20 token = IERC20(escrow.currency);
            
            // Transfer token from sender to this contract
            require(token.transferFrom(msg.sender, address(this), escrow.amount), "Token transfer failed");
        }
        
        // Update escrow state
        escrow.state = EscrowState.Funded;
        
        emit EscrowFunded(_escrowId, msg.sender);
    }
    
    /**
     * @dev Complete the escrow and release funds to the merchant
     * @param _escrowId The unique identifier for the escrow
     */
    function completeEscrow(bytes32 _escrowId) external nonReentrant validEscrow(_escrowId) {
        Escrow storage escrow = escrows[_escrowId];
        
        require(msg.sender == escrow.buyer, "Only buyer can complete the escrow");
        require(escrow.state == EscrowState.Funded, "Escrow is not in Funded state");
        
        // Process payment and fees
        _processPayment(escrow);
        
        // Update escrow state
        escrow.state = EscrowState.Completed;
        
        emit EscrowCompleted(_escrowId);
    }
    
    /**
    * @dev Refund the escrowed amount back to the buyer
    * @param _escrowId The unique identifier for the escrow
    */
    function refundEscrow(bytes32 _escrowId) external nonReentrant validEscrow(_escrowId) {
        Escrow storage escrow = escrows[_escrowId];
        
        // Only merchant can refund
        require(msg.sender == escrow.merchant, "Only merchant can refund");
        require(escrow.state == EscrowState.Funded, "Escrow is not in Funded state");
        
        if (escrow.currency == address(0)) {
            // ETH refund
            (bool sent, ) = escrow.buyer.call{value: escrow.amount}("");
            require(sent, "Failed to send ETH");
        } else {
            // ERC20 token refund
            IERC20 token = IERC20(escrow.currency);
            require(token.transfer(escrow.buyer, escrow.amount), "Token transfer failed");
        }
        
        // Update escrow state
        escrow.state = EscrowState.Refunded;
        
        emit EscrowRefunded(_escrowId);
    }
    
    /**
     * @dev Raise a dispute for an escrow
     * @param _escrowId The unique identifier for the escrow
     * @param _reason Reason for the dispute
     */
    function raiseDispute(bytes32 _escrowId, string calldata _reason) external validEscrow(_escrowId) {
        Escrow storage escrow = escrows[_escrowId];
        
        require(
            msg.sender == escrow.buyer || msg.sender == escrow.merchant,
            "Only buyer or merchant can raise a dispute"
        );
        require(escrow.state == EscrowState.Funded, "Escrow is not in Funded state");
        require(bytes(_reason).length > 0, "Reason must be provided");
        
        // Update escrow state
        escrow.state = EscrowState.Disputed;
        escrow.disputeReason = _reason;
        
        emit DisputeRaised(_escrowId, _reason);
    }
    
    /**
     * @dev Resolve a disputed escrow (only arbitrator)
     * @param _escrowId The unique identifier for the escrow
     * @param _merchantPercent Percentage of funds to send to merchant (0-100)
     */
    function resolveDispute(bytes32 _escrowId, uint256 _merchantPercent) external onlyArbitrator validEscrow(_escrowId) {
        Escrow storage escrow = escrows[_escrowId];
        
        require(escrow.state == EscrowState.Disputed, "Escrow is not in Disputed state");
        require(_merchantPercent <= 100, "Merchant percentage must be between 0-100");
        
        uint256 merchantAmount = (escrow.amount * _merchantPercent) / 100;
        uint256 buyerAmount = escrow.amount - merchantAmount;
        
        // Process the split payment
        if (escrow.currency == address(0)) {
            // ETH split
            if (merchantAmount > 0) {
                (bool sentMerchant, ) = escrow.merchant.call{value: merchantAmount}("");
                require(sentMerchant, "Failed to send ETH to merchant");
            }
            
            if (buyerAmount > 0) {
                (bool sentBuyer, ) = escrow.buyer.call{value: buyerAmount}("");
                require(sentBuyer, "Failed to send ETH to buyer");
            }
        } else {
            // ERC20 token split
            IERC20 token = IERC20(escrow.currency);
            
            if (merchantAmount > 0) {
                require(token.transfer(escrow.merchant, merchantAmount), "Transfer to merchant failed");
            }
            
            if (buyerAmount > 0) {
                require(token.transfer(escrow.buyer, buyerAmount), "Transfer to buyer failed");
            }
        }
        
        // Update escrow state
        escrow.state = EscrowState.Resolved;
        
        // Determine the winner based on who received more
        address winner = merchantAmount > buyerAmount ? escrow.merchant : escrow.buyer;
        if (merchantAmount == buyerAmount) {
            winner = address(0); // Tie - no winner
        }
        
        emit DisputeResolved(_escrowId, winner, merchantAmount, buyerAmount);
    }
    
    /**
     * @dev Process payment with fee calculation
     * @param escrow The escrow struct containing payment details
     */
    function _processPayment(Escrow storage escrow) private {
        // Calculate platform fee
        uint256 fee = (escrow.amount * platformFeeRate) / 10000;
        uint256 merchantAmount = escrow.amount - fee;
        
        if (escrow.currency == address(0)) {
            // ETH payment
            // Send to merchant
            (bool sentMerchant, ) = escrow.merchant.call{value: merchantAmount}("");
            require(sentMerchant, "Failed to send ETH to merchant");
            
            // Send fee
            (bool sentFee, ) = feeCollector.call{value: fee}("");
            require(sentFee, "Failed to send fee");
        } else {
            // ERC20 token payment
            IERC20 token = IERC20(escrow.currency);
            
            // Transfer tokens to merchant and fee collector
            require(token.transfer(escrow.merchant, merchantAmount), "Transfer to merchant failed");
            require(token.transfer(feeCollector, fee), "Transfer of fee failed");
        }
    }
    
    /**
     * @dev Get escrow details
     * @param _escrowId The unique identifier for the escrow
     */
    function getEscrow(bytes32 _escrowId) external view returns (
        address merchant,
        address buyer,
        uint256 amount,
        address currency,
        EscrowState state,
        uint256 deadline,
        string memory description,
        string memory disputeReason
    ) {
        Escrow storage escrow = escrows[_escrowId];
        return (
            escrow.merchant,
            escrow.buyer,
            escrow.amount,
            escrow.currency,
            escrow.state,
            escrow.deadline,
            escrow.description,
            escrow.disputeReason
        );
    }
    
    /**
     * @dev Generate a receipt for an escrow
     * @param _escrowId The unique identifier for the escrow
     * @return receiptId Unique identifier for the receipt
     */
    function generateReceipt(bytes32 _escrowId) external validEscrow(_escrowId) returns (bytes32 receiptId) {
        Escrow storage escrow = escrows[_escrowId];
        
        // Only allow receipt generation for completed or refunded escrows
        require(
            escrow.state == EscrowState.Completed || 
            escrow.state == EscrowState.Refunded || 
            escrow.state == EscrowState.Resolved,
            "Escrow must be completed, refunded, or resolved"
        );
        
        // Generate unique receipt ID
        receiptId = keccak256(abi.encodePacked(_escrowId, block.timestamp, msg.sender));
        
        // Store receipt information
        receipts[receiptId] = true;
        
        // Emit receipt event
        emit ReceiptGenerated(receiptId, _escrowId, msg.sender, block.timestamp);
        
        return receiptId;
    }

    /**
    * @dev Claim a refund after the escrow deadline has passed
    * @param _escrowId The unique identifier for the escrow
    */
    function claimExpiredEscrow(bytes32 _escrowId) external nonReentrant validEscrow(_escrowId) {
        Escrow storage escrow = escrows[_escrowId];
        
        require(msg.sender == escrow.buyer, "Only buyer can claim expired funds");
        require(escrow.state == EscrowState.Funded, "Escrow is not in Funded state");
        require(block.timestamp > escrow.deadline, "Escrow deadline has not passed");
        
        if (escrow.currency == address(0)) {
            // ETH refund
            (bool sent, ) = escrow.buyer.call{value: escrow.amount}("");
            require(sent, "Failed to send ETH");
        } else {
            // ERC20 token refund
            IERC20 token = IERC20(escrow.currency);
            require(token.transfer(escrow.buyer, escrow.amount), "Token transfer failed");
        }
        
        // Update escrow state
        escrow.state = EscrowState.Refunded;
        
        emit EscrowRefunded(_escrowId);
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
     * @dev Update the arbitrator address (owner only)
     * @param _newArbitrator New arbitrator address
     */
    function updateArbitrator(address _newArbitrator) external onlyOwner {
        require(_newArbitrator != address(0), "Invalid arbitrator address");
        address oldArbitrator = arbitrator;
        arbitrator = _newArbitrator;
        emit ArbitratorChanged(oldArbitrator, _newArbitrator);
    }
    
    /**
     * @dev Update platform fee rate (owner only)
     * @param _newFeeRate New fee rate in basis points (e.g., 100 = 1%)
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
    
    /**
     * @dev Update the default escrow period in days (owner only)
     * @param _days New default escrow period in days
     */
    function updateDefaultEscrowDays(uint256 _days) external onlyOwner {
        require(_days > 0 && _days <= 365, "Invalid escrow period");
        defaultEscrowDays = _days;
    }
    
    /**
     * @dev Check if an escrow exists and is active
     * @param _escrowId The unique identifier for the escrow
     * @return exists Whether the escrow exists
     * @return isActive Whether the escrow is in an active state
     */
    function checkEscrowStatus(bytes32 _escrowId) external view returns (bool exists, bool isActive) {
        Escrow storage escrow = escrows[_escrowId];
        exists = escrow.merchant != address(0);
        isActive = exists && (escrow.state == EscrowState.Created || escrow.state == EscrowState.Funded);
        return (exists, isActive);
    }
    
    /**
     * @dev Function to receive ETH payments
     */
    receive() external payable {
        // Silently accept ETH
    }
    
    /**
     * @dev Fallback function
     */
    fallback() external payable {
        // Silently accept ETH
    }
}