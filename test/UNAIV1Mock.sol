/*
██╗   ██╗███╗   ██╗██╗  ██╗███╗   ██╗ ██████╗ ██╗    ██╗███╗   ██╗     █████╗ ██╗
██║   ██║████╗  ██║██║ ██╔╝████╗  ██║██╔═══██╗██║    ██║████╗  ██║    ██╔══██╗██║
██║   ██║██╔██╗ ██║█████╔╝ ██╔██╗ ██║██║   ██║██║ █╗ ██║██╔██╗ ██║    ███████║██║
██║   ██║██║╚██╗██║██╔═██╗ ██║╚██╗██║██║   ██║██║███╗██║██║╚██╗██║    ██╔══██║██║
╚██████╔╝██║ ╚████║██║  ██╗██║ ╚████║╚██████╔╝╚███╔███╔╝██║ ╚████║    ██║  ██║██║
╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝  ╚══╝╚══╝ ╚═╝  ╚═══╝    ╚═╝  ╚═╝╚═╝
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// ---------------------------------------
// Interfaces for Uniswap V2 Router & Factory
// ---------------------------------------
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

contract Contract is ERC20, Ownable {
    uint256 public constant TOTAL_SUPPLY = 100 * 1e6 * 1e18;
    // ---------------------------------------
    // Fee and Address Config
    // ---------------------------------------
    // Buy fees
    uint256 public buyOperationsFee = 3; // 3%
    uint256 public buyDevFee = 1; // 1%
    uint256 public buyTotalFees = 4; // 3 + 1

    // Sell fees
    uint256 public sellOperationsFee = 3; // 3%
    uint256 public sellDevFee = 1; // 1%
    uint256 public sellTotalFees = 4; // 3 + 1

    // Where to send the fees
    address public operationsAddress;
    address public devAddress;

    // Token counters for pending fees
    uint256 public tokensForOperations;
    uint256 public tokensForDev;

    // ---------------------------------------
    // DEX Router / Pair
    // ---------------------------------------
    IUniswapV2Router02 public dexRouter;
    address public lpPair;

    // ---------------------------------------
    // Swap Configuration
    // ---------------------------------------
    bool public swapEnabled = true;
    bool private swapping; // internal lock for swapBack
    uint256 public swapTokensAtAmount; // threshold for auto-swap

    constructor(address _operationsAddress, address _devAddress)
        ERC20("Unknown AI V1", "UNAIV1")
        Ownable(msg.sender)
    {
        require(_operationsAddress != address(0), "Ops address cannot be zero");
        require(_devAddress != address(0), "Dev address cannot be zero");

        // ---------------------------------------
        // Set Fee Addresses
        // ---------------------------------------
        operationsAddress = _operationsAddress;
        devAddress = _devAddress;

        // ---------------------------------------
        // DEX Router & Pair Creation
        // ---------------------------------------
        // dexRouter = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D); //mainnet
        dexRouter = IUniswapV2Router02(0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008); //sepolia
        lpPair = IUniswapV2Factory(dexRouter.factory()).createPair(address(this), dexRouter.WETH());

        // ---------------------------------------
        // Mint total supply to owner
        // ---------------------------------------
        _mint(msg.sender, TOTAL_SUPPLY);

        // ---------------------------------------
        // Set a default threshold for auto-swaps
        // e.g. 0.05% of total supply
        // ---------------------------------------
        swapTokensAtAmount = (TOTAL_SUPPLY * 5) / 10_000; // 0.05%

        // Exclude contract from fees by default, so it won't tax itself during swaps
        // (We do this by checking `from == address(this)` or `to == address(this)` in _transfer)
    }

    // ---------------------------------------
    // Owner-Only Functions: Adjust Fees, etc.
    // ---------------------------------------
    function updateBuyFees(uint256 _opsFee, uint256 _devFee) external onlyOwner {
        buyOperationsFee = _opsFee;
        buyDevFee = _devFee;
        buyTotalFees = _opsFee + _devFee;
        require(buyTotalFees <= 10, "Buy fees cannot exceed 10%");
    }

    function updateSellFees(uint256 _opsFee, uint256 _devFee) external onlyOwner {
        sellOperationsFee = _opsFee;
        sellDevFee = _devFee;
        sellTotalFees = _opsFee + _devFee;
        require(sellTotalFees <= 10, "Sell fees cannot exceed 10%");
    }

    function updateOperationsAddress(address _ops) external onlyOwner {
        require(_ops != address(0), "Ops address cannot be zero");
        operationsAddress = _ops;
    }

    function updateDevAddress(address _dev) external onlyOwner {
        require(_dev != address(0), "Dev address cannot be zero");
        devAddress = _dev;
    }

    function setSwapTokensAtAmount(uint256 newAmount) external onlyOwner {
        require(newAmount > 0, "Amount must be > 0");
        swapTokensAtAmount = newAmount;
    }

    function setSwapEnabled(bool enabled) external onlyOwner {
        swapEnabled = enabled;
    }

    // ---------------------------------------
    // Core Transfer Logic
    // ---------------------------------------
    function _update(address from, address to, uint256 amount) internal override {
        require(amount > 0, "Transfer amount must be > 0");

        bool takeFee = true;

        // If contract is sending or receiving, skip fees
        if (from == address(this) || to == address(this)) {
            takeFee = false;
        }

        // If there's a sell or buy:
        //   - buy if from == lpPair
        //   - sell if to == lpPair
        // Otherwise no fees for normal transfers.
        bool isBuy = (from == lpPair && to != address(dexRouter));
        bool isSell = (to == lpPair && from != address(dexRouter));

        // ---------------------------------------
        // Check if we should swap first (only on sells typically)
        // ---------------------------------------
        uint256 contractTokenBalance = balanceOf(address(this));
        bool canSwap = (contractTokenBalance >= swapTokensAtAmount);

        if (
            canSwap && !swapping && swapEnabled && isSell // usually we only want to trigger on sells
        ) {
            swapping = true;
            _swapBack();
            swapping = false;
        }

        // ---------------------------------------
        // Take Fees if it's a buy/sell
        // ---------------------------------------
        if (takeFee) {
            uint256 fees = 0;

            if (isBuy && buyTotalFees > 0) {
                fees = (amount * buyTotalFees) / 100;
                uint256 opsPart = (fees * buyOperationsFee) / buyTotalFees;
                tokensForOperations += opsPart;
                tokensForDev += (fees - opsPart);
            } else if (isSell && sellTotalFees > 0) {
                fees = (amount * sellTotalFees) / 100;
                uint256 opsPart = (fees * sellOperationsFee) / sellTotalFees;
                tokensForOperations += opsPart;
                tokensForDev += (fees - opsPart);
            }

            if (fees > 0) {
                super._update(from, address(this), fees);
                amount -= fees;
            }
        }

        // ---------------------------------------
        // Final Transfer
        // ---------------------------------------
        super._update(from, to, amount);
    }

    // ---------------------------------------
    // Swap & Distribute
    // ---------------------------------------
    function _swapBack() private {
        // how many tokens are we swapping?
        uint256 totalTokensToSwap = tokensForOperations + tokensForDev;
        if (totalTokensToSwap == 0) {
            return;
        }

        uint256 contractBalance = balanceOf(address(this));
        if (contractBalance < totalTokensToSwap) {
            // safety check
            totalTokensToSwap = contractBalance;
        }

        // Track how many go to ops vs dev
        uint256 amountForOps = tokensForOperations;

        // Reset counters
        tokensForOperations = 0;
        tokensForDev = 0;

        // 1) Swap all tokens for ETH
        _swapTokensForEth(totalTokensToSwap);

        // 2) Distribute ETH
        uint256 ethBalance = address(this).balance;
        if (ethBalance == 0) return;

        // ops share
        uint256 ethForOps = (ethBalance * amountForOps) / totalTokensToSwap;
        // dev share
        uint256 ethForDev = ethBalance - ethForOps;

        (bool successOps,) = operationsAddress.call{value: ethForOps}("");
        require(successOps, "Ops ETH transfer failed");

        (bool successDev,) = devAddress.call{value: ethForDev}("");
        require(successDev, "Dev ETH transfer failed");
    }

    function _swapTokensForEth(uint256 tokenAmount) private {
        _approve(address(this), address(dexRouter), tokenAmount);

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = dexRouter.WETH();

        // Do the swap; funds arrive as ETH in this contract
        dexRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    // Allow contract to receive ETH when swapping
    receive() external payable {}
}
