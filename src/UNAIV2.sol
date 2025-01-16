// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

interface IERC20 {
    event Transfer(address indexed sender, address indexed recipient, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount)
        external
        returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IUniswapV2Router02 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

contract UNAI is IERC20, Ownable {
    /* ========== EVENTS ========== */
    event SwapSettingsUpdated(uint256 newThreshold, uint256 newMaxAmount);
    event TaxCollectorUpdated(address newCollector);
    event ExemptFromTaxes(address account, bool enabled);

    /* ========== STATE VARIABLES ========== */
    string private constant _name = "Unknown AI";
    string private constant _symbol = "UNAI";
    uint8 private constant _decimals = 18;
    uint256 private constant _totalSupply = 42_000_000 * 10 ** _decimals;

    uint256 private _swapLocked = 1;
    uint256 private _swapThreshold = (_totalSupply * 5) / 10_000;
    uint256 private _maxSwapAmount = (_totalSupply * 5) / 1000;

    IUniswapV2Router02 private immutable _dexRouter;
    address private immutable _liquidityPool;

    uint256 private constant _buyTax = 300;
    uint256 private constant _sellTax = 500;
    address payable public taxCollector;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) private _taxExempt;

    /* ========== ERRORS ========== */
    error Reentrancy();

    /* ========== CONSTRUCTOR ========== */
    constructor(address payable _taxCollector, address routerAddress) Ownable(msg.sender) {
        require(_taxCollector != address(0), "Invalid address");
        taxCollector = _taxCollector;

        _taxExempt[0x000000000000000000000000000000000000dEaD] = true;
        _taxExempt[address(this)] = true;
        _taxExempt[msg.sender] = true;
        _taxExempt[_taxCollector] = true;

        _dexRouter = IUniswapV2Router02(routerAddress);
        _liquidityPool =
            IUniswapV2Factory(_dexRouter.factory()).createPair(address(this), _dexRouter.WETH());

        _balances[msg.sender] = _totalSupply;
        _allowances[address(this)][address(_dexRouter)] = type(uint256).max;

        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    /* ========== MODIFIERS ========== */
    modifier lockTheSwap() virtual {
        if (_swapLocked == 2) revert Reentrancy();

        _swapLocked = 2;
        _;
        _swapLocked = 1;
    }

    /* ========== VIEW FUNCTIONS ========== */
    function name() external pure override returns (string memory) {
        return _name;
    }

    function symbol() external pure override returns (string memory) {
        return _symbol;
    }

    function decimals() external pure override returns (uint8) {
        return _decimals;
    }

    function totalSupply() external pure override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function isTaxExempt(address account) external view returns (bool) {
        return _taxExempt[account];
    }

    function getPoolAddress() external view returns (address) {
        return _liquidityPool;
    }

    /* ========== PRIVATE FUNCTIONS ========== */
    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: Approve from zero address");
        require(spender != address(0), "ERC20: Approve to zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(address sender, address recipient, uint256 amount) private {
        require(sender != address(0), "Transfer from zero address");
        require(recipient != address(0), "Transfer to zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "Insufficient balance");

        bool isExcluded = _taxExempt[sender] || _taxExempt[recipient];
        bool isLiquidityPool = sender == _liquidityPool || recipient == _liquidityPool;
        uint256 transferAmount = amount;

        if (!isExcluded && isLiquidityPool) {
            uint256 transactionTax = _buyTax;
            if (recipient == _liquidityPool) {
                transactionTax = _sellTax;
            }

            uint256 taxAmount = (amount * transactionTax) / 10_000;
            if (taxAmount > 0) {
                _balances[address(this)] += taxAmount;
                emit Transfer(sender, address(this), taxAmount);

                transferAmount -= taxAmount;
            }
        }

        _balances[sender] -= amount;
        _balances[recipient] += transferAmount;
        emit Transfer(sender, recipient, transferAmount);
    }

    function _swapTokensForEth(uint256 tokenAmount) private lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = _dexRouter.WETH();

        _dexRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount, 0, path, taxCollector, block.timestamp
        );
    }

    /* ========== EXTERNAL FUNCTIONS ========== */
    function transfer(address recipient, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount)
        external
        override
        returns (bool)
    {
        if (_allowances[sender][msg.sender] != type(uint256).max) {
            _approve(sender, msg.sender, _allowances[sender][msg.sender] - amount);
        }

        _transfer(sender, recipient, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    receive() external payable {}

    /* ========== OWNER FUNCTIONS ========== */
    function setSwapSettings(uint256 threshold, uint256 maxAmount) external onlyOwner {
        require(threshold > 0, "Invalid threshold");
        require(maxAmount > 0, "Invalid max amount");

        _swapThreshold = (_totalSupply * threshold) / 10_000;
        _maxSwapAmount = (_totalSupply * maxAmount) / 1000;

        emit SwapSettingsUpdated(_swapThreshold, _maxSwapAmount);
    }

    function setTaxCollector(address payable _taxCollector) external onlyOwner {
        require(_taxCollector != address(0), "Invalid address");

        taxCollector = _taxCollector;
        emit TaxCollectorUpdated(_taxCollector);
    }

    function setTaxExempt(address account, bool enabled) external onlyOwner {
        require(account != address(0), "Invalid address");

        _taxExempt[account] = enabled;
        emit ExemptFromTaxes(account, enabled);
    }

    function triggerSwap() external onlyOwner {
        uint256 contractBalance = _balances[address(this)];
        if (contractBalance >= _swapThreshold) {
            if (contractBalance > _maxSwapAmount) {
                contractBalance = _maxSwapAmount;
            }

            _swapTokensForEth(contractBalance);
        }
    }
}
