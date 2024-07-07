// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

 contract QuantumElysiumBloom is Initializable, Ownable, UUPSUpgradeable, ReentrancyGuard {
    // Constructor with owner argument passed to base contracts.
    constructor() Ownable(msg.sender) ReentrancyGuard() {} 
    
    using SafeERC20 for IERC20;
    using Address for address;

    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public qebTokenAddress;
    uint256 public qebToEthRate;

    address public defiProtocolAddress;
    address public uniswapV3PositionAddress;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Pause();
    event Unpause();
    event DepositETH(address indexed depositor, uint256 amount);
    event WithdrawETHWithQEB(address indexed recipient, uint256 ethAmount, uint256 qebAmount);
    event DepositToDefiProtocol(address indexed depositor, uint256 amount);
    event WithdrawFromDefiProtocol(address indexed recipient, uint256 amount);
    event SwapETHForQEBV3(address indexed recipient, uint256 ethAmount);
    event SwapQEBForETHV3(address indexed recipient, uint256 qebAmount);
    event UniswapV3PositionAddressSet(address indexed newAddress);
    event BaseRewardRateSet(uint256 newRate);
    event MinimumRewardSet(uint256 newMinimum);

    bool private _paused;
    mapping(address => bool) private _owners;
    mapping(address => bool) private _restrictedOwners;

    modifier whenNotPaused() {
        require(!_paused, "Contract is paused");
        _;
    }

    modifier onlyOwnerOrAuthorized() {
        require(msg.sender == owner() || _owners[msg.sender], "Caller is not the owner or authorized");
        _;
    }

    modifier whenNotRestrictedOwner() {
        require(!_restrictedOwners[msg.sender], "Restricted owners cannot perform this action");
        _;
    }

     function initialize() public initializer {
        name = "Quantum Elysium Bloom";
        symbol = "QEB";
        decimals = 18;
        totalSupply = 50000000 * 10**18; // Total supply of 50,000,000 QEB tokens

        // Mint tokens to the contract deployer (msg.sender) during deployment
        balanceOf[msg.sender] = totalSupply;

        _paused = false;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function transfer(address _to, uint256 _value) public whenNotPaused returns (bool success) {
        _transfer(msg.sender, _to, _value);
        return true;
    }

    function _transfer(address _from, address _to, uint256 _value) internal {
        require(_to != address(0), "Invalid recipient address");
        require(balanceOf[_from] >= _value, "Insufficient balance");

        balanceOf[_from] -= _value;
        balanceOf[_to] += _value;

        emit Transfer(_from, _to, _value);
    }

    function approve(address _spender, uint256 _value) public whenNotPaused returns (bool success) {
        allowance[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _value) public whenNotPaused returns (bool success) {
        require(_value <= allowance[_from][msg.sender], "Allowance exceeded");

        allowance[_from][msg.sender] -= _value;
        _transfer(_from, _to, _value);

        return true;
    }

    function increaseAllowance(address _spender, uint256 _addedValue) public whenNotPaused returns (bool) {
        allowance[msg.sender][_spender] += _addedValue;
        emit Approval(msg.sender, _spender, allowance[msg.sender][_spender]);
        return true;
    }

    function decreaseAllowance(address _spender, uint256 _subtractedValue) public whenNotPaused returns (bool) {
        uint256 oldValue = allowance[msg.sender][_spender];
        if (_subtractedValue >= oldValue) {
            allowance[msg.sender][_spender] = 0;
        } else {
            allowance[msg.sender][_spender] = oldValue - _subtractedValue;
        }
        emit Approval(msg.sender, _spender, allowance[msg.sender][_spender]);
        return true;
    }

    function mint(address _account, uint256 _amount) public onlyOwnerOrAuthorized whenNotRestrictedOwner {
        require(_account != address(0), "Invalid account address");
        totalSupply += _amount;
        balanceOf[_account] += _amount;
        emit Transfer(address(0), _account, _amount);
    }

    function burn(uint256 _amount) public {
        require(balanceOf[msg.sender] >= _amount, "Insufficient balance to burn");
        _transfer(msg.sender, address(0), _amount);
        totalSupply -= _amount;
        emit Transfer(msg.sender, address(0), _amount);
    }

    function setOwner(address _newOwner) public onlyOwner {
        require(_newOwner != address(0), "Invalid owner address");
        emit OwnershipTransferred(owner(), _newOwner);
        transferOwnership(_newOwner);
    }

    function addOwner(address _newOwner) public onlyOwner {
        require(_newOwner != address(0), "Invalid owner address");
        _owners[_newOwner] = true;
    }

    function removeOwner(address _ownerAddress) public onlyOwner {
        require(_ownerAddress != owner(), "Cannot remove yourself as owner");
        _owners[_ownerAddress] = false;
    }

    function checkOwners(address _ownerAddress) public view returns (bool) {
        return _owners[_ownerAddress];
    }

    function pause() public onlyOwnerOrAuthorized {
        _paused = true;
        emit Pause();
    }

    function unpause() public onlyOwnerOrAuthorized {
        _paused = false;
        emit Unpause();
    }

    receive() external payable {
        depositETH();
    }

    function calculateRewardRate(uint256 _amount, uint256 _timestamp) private view returns (uint256) {
        uint256 timeDelta = block.timestamp - _timestamp; // Time elapsed since deposit
        uint256 rewardRate = _amount * 1 / 10000; // 1% base reward per day
        uint256 reward = rewardRate * timeDelta / 86400; // Apply time delta (assuming daily rate)
        return reward;
    }

    function depositETH() public payable nonReentrant {
        require(msg.value > 0, "Deposit amount must be greater than 0");
        uint256 reward = calculateRewardRate(msg.value, block.timestamp);
        _mint(msg.sender, reward);
        emit DepositETH(msg.sender, msg.value);
    }

    function _mint(address account, uint256 amount) internal {
        totalSupply += amount;
        balanceOf[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function withdrawETHWithQEB(uint256 _ethAmount) public nonReentrant {
        require(_ethAmount > 0, "Withdrawal amount must be greater than 0");
        require(address(this).balance >= _ethAmount, "Insufficient contract ETH balance");
        
        // Calculate QEB amount to exchange based on exchange rate
        uint256 qebAmount = _ethAmount * qebToEthRate;
        require(balanceOf[msg.sender] >= qebAmount, "Insufficient QEB balance for withdrawal");
        
        _transfer(msg.sender, address(this), qebAmount); // Burn QEB
        payable(msg.sender).transfer(_ethAmount); // Send ETH to user
        
        emit WithdrawETHWithQEB(msg.sender, _ethAmount, qebAmount);
    }

   // DeFi Protocol Integration (example using IERC20)
   function depositToDefiProtocol(address _tokenAddress, uint256 _amount) public onlyOwnerOrAuthorized {
       require(_tokenAddress != address(0), "Invalid token address");
       require(_amount > 0, "Deposit amount must be greater than 0");
       IERC20 token = IERC20(_tokenAddress);
       require(token.balanceOf(address(this)) >= _amount, "Insufficient token balance for deposit");
       
       // Approve DeFi protocol to spend tokens
       token.approve(defiProtocolAddress, _amount);
       
       // Call DeFi protocol deposit function (replace with specific function call)
       // ... (interaction with DeFi protocol)
       
       emit DepositToDefiProtocol(msg.sender, _amount);
   }

   // DeFi Protocol Withdrawal (example using IERC20)
   function withdrawFromDefiProtocol(address _tokenAddress, uint256 _amount) public onlyOwnerOrAuthorized {
       require(_tokenAddress != address(0), "Invalid token address");
       require(_amount > 0, "Withdrawal amount must be greater than 0");
       
       // Call DeFi protocol withdrawal function (replace with specific function call)
       // ... (interaction with DeFi protocol)
       
       // DeFi protocol should transfer tokens back to this contract
       
       emit WithdrawFromDefiProtocol(msg.sender, _amount);
   }

   // Uniswap V3 Integration (example using IUniswapV3Pool)
  function getUniswapV3Price() public view returns (uint256) {
        require(uniswapV3PositionAddress != address(0), "UniswapV3 position not set");

        IUniswapV3Pool pool = IUniswapV3Pool(uniswapV3PositionAddress);
        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();

        // Convert sqrtPriceX96 to decimal price for desired token (replace with specific logic)
        // This is a placeholder logic, replace with your actual calculation based on pool tokens and decimals
        uint256 price = uint256(sqrtPriceX96) ** 2 / (1 << 192); // Simplified conversion for demonstration

        return price; // Return calculated price
    }

   function swapETHForQEBV3(uint256 _ethAmount) public payable nonReentrant {
       require(_ethAmount > 0, "Swap amount must be greater than 0");
       require(uniswapV3PositionAddress != address(0), "UniswapV3 position not set");
       
       // Call Uniswap V3 swap function to exchange ETH for QEB (replace with specific call)
       // ... (interaction with Uniswap V3)
       
       emit SwapETHForQEBV3(msg.sender, _ethAmount);
   }

   function swapQEBForETHV3(uint256 _qebAmount) public nonReentrant {
       require(_qebAmount > 0, "Swap amount must be greater than 0");
       require(uniswapV3PositionAddress != address(0), "Uniswap V3 position not set");
       require(balanceOf[msg.sender] >= _qebAmount, "Insufficient QEB balance for swap");
       
       // Approve Uniswap V3 to spend QEB tokens
       allowance[msg.sender][uniswapV3PositionAddress] = _qebAmount;
       emit Approval(msg.sender, uniswapV3PositionAddress, _qebAmount);
       
       // Call Uniswap V3 swap function 
       // ... (interaction with Uniswap V3 to exchange QEB for ETH)
       
       _transfer(msg.sender, uniswapV3PositionAddress, _qebAmount); // Transfer QEB to Uniswap V3 pool
       
       emit SwapQEBForETHV3(msg.sender, _qebAmount);
   }

   // Setters for configuration
  
   function setQebTokenAddress(address _qebTokenAddress) public onlyOwner {
       qebTokenAddress = _qebTokenAddress;
   }

   function setQebToEthRate(uint256 _rate) public onlyOwner {
       qebToEthRate = _rate;
   }

   function setDefiProtocolAddress(address _defiProtocolAddress) public onlyOwner {
       defiProtocolAddress = _defiProtocolAddress;
   }

   function setUniswapV3PositionAddress(address _uniswapV3Position) public onlyOwner {
       uniswapV3PositionAddress = _uniswapV3Position;
   }

   // Restricted functions (to prevent abuse by some owners)
   function addRestrictedOwner(address _newOwner) public onlyOwner {
       require(_newOwner != address(0), "Invalid owner address");
       _restrictedOwners[_newOwner] = true;
   }

   function removeRestrictedOwner(address _ownerAddress) public onlyOwner {
       require(_ownerAddress != owner(), "Cannot remove yourself as owner");
       _restrictedOwners[_ownerAddress] = false;
   }  

   // Function to remove ETH with QEB
   function removeETHWithQEB(uint256 _ethAmount, uint256 _qebAmount) public nonReentrant {
       require(_ethAmount > 0, "Withdrawal amount must be greater than 0");
       require(_qebAmount > 0, "QEB amount must be greater than 0");
       require(address(this).balance >= _ethAmount, "Insufficient contract ETH balance");
       require(balanceOf[msg.sender] >= _qebAmount, "Insufficient QEB balance for withdrawal");

       uint256 calculatedQEBAmount = _ethAmount * qebToEthRate;
       require(calculatedQEBAmount == _qebAmount, "Incorrect QEB amount");

       _transfer(msg.sender, address(this), _qebAmount); // Burn QEB
       payable(msg.sender).transfer(_ethAmount); // Send ETH to user

       emit WithdrawETHWithQEB(msg.sender, _ethAmount, _qebAmount);
   }

   // Time lock for critical operations
   uint256 public timeLockDuration = 1 days;
   mapping(bytes32 => uint256) public timeLocks;

   function setTimeLockDuration(uint256 _duration) external onlyOwner {
       timeLockDuration = _duration;
   }

   modifier onlyAfterTimeLock(bytes32 lockId) {
       require(timeLocks[lockId] <= block.timestamp, "Function is time-locked");
       _;
   }

   function lockFunction(bytes32 lockId) external onlyOwner {
       timeLocks[lockId] = block.timestamp + timeLockDuration;
   }

   // Blacklist functionality
   mapping(address => bool) public blacklist;

   function addToBlacklist(address _address) external onlyOwner {
       blacklist[_address] = true;
   }

   function removeFromBlacklist(address _address) external onlyOwner {
       blacklist[_address] = false;
   }

   modifier notBlacklisted(address _address) {
       require(!blacklist[_address], "Address is blacklisted");
       _;
   }

   // Tolerance for slippage and fees
   uint256 public slippageTolerance;
   uint256 public swapFee;

   function setSlippageTolerance(uint256 _slippageTolerance) external onlyOwner {
       slippageTolerance = _slippageTolerance;
   }

   function setSwapFee(uint256 _swapFee) external onlyOwner {
       swapFee = _swapFee;
   }

   // Swap functions with slippage tolerance and fee handling
   function swapExactETHForQEBV3(uint256 _ethAmount) public payable nonReentrant {
       require(_ethAmount > 0, "Swap amount must be greater than 0");
       require(uniswapV3PositionAddress != address(0), "UniswapV3 position not set");

       // Call Uniswap V3 swap function to exchange ETH for QEB with slippage tolerance and fee
       // ... (interaction with Uniswap V3)
       
       emit SwapETHForQEBV3(msg.sender, _ethAmount);
   }

   function swapExactQEBForETHV3(uint256 _qebAmount) public nonReentrant {
       require(_qebAmount > 0, "Swap amount must be greater than 0");
       require(uniswapV3PositionAddress != address(0), "Uniswap V3 position not set");
       require(balanceOf[msg.sender] >= _qebAmount, "Insufficient QEB balance for swap");

       // Approve Uniswap V3 to spend QEB tokens
       allowance[msg.sender][uniswapV3PositionAddress] = _qebAmount;
       emit Approval(msg.sender, uniswapV3PositionAddress, _qebAmount);

       // Call Uniswap V3 swap function with slippage tolerance and fee handling
       // ... (interaction with Uniswap V3 to exchange QEB for ETH)

       _transfer(msg.sender, uniswapV3PositionAddress, _qebAmount); // Transfer QEB to Uniswap V3 pool

       emit SwapQEBForETHV3(msg.sender, _qebAmount);
   }
}