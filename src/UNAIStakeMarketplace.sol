// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IStakingVault {
    function transferStake(address from, address to, uint256 stakeId) external;
    function userStakes(address user, uint256 stakeId)
        external
        view
        returns (
            uint256 amount,
            uint256 startTime,
            uint256 lockDuration,
            uint256 shares,
            uint256 rewardDebt
        );
    function pendingRewards(address user, uint256 stakeId) external view returns (uint256);
}

interface IDEXRouter {
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

contract UNAIStakeMarketplace is ReentrancyGuard, Ownable {
    IStakingVault public stakingVault;
    IERC20 public paymentToken;
    IDEXRouter public dexRouter;
    address public wethAddress;

    uint256 public marketplaceFee; // Fee in basis points (e.g., 100 = 1%)

    struct Listing {
        uint256 stakeId;
        bool active;
        bool fulfilled;
        address seller;
        uint256 price;
        uint256 timestamp;
    }

    mapping(uint256 => Listing) public listings;
    uint256 public nextListingId;

    event ListingCreated(
        uint256 indexed listingId,
        address indexed seller,
        uint256 stakeId,
        uint256 price,
        uint256 timestamp
    );
    event ListingCancelled(uint256 indexed listingId);
    event ListingFulfilled(uint256 indexed listingId, address indexed buyer);
    event ListingUpdated(uint256 indexed listingId, uint256 newPrice);
    event MarketplaceFeeUpdated(uint256 newFee);

    constructor(address _stakingVault, address _paymentToken, address _dexRouter)
        Ownable(msg.sender)
    {
        stakingVault = IStakingVault(_stakingVault);
        paymentToken = IERC20(_paymentToken);
        dexRouter = IDEXRouter(_dexRouter);
        wethAddress = dexRouter.WETH();
        marketplaceFee = 400; // 4%
    }

    function setMarketplaceFee(uint256 _fee) external onlyOwner {
        require(_fee <= 1000, "Fee cannot exceed 10%");
        marketplaceFee = _fee;
        emit MarketplaceFeeUpdated(_fee);
    }

    function createListing(uint256 stakeId, uint256 price) external nonReentrant {
        (uint256 amount,,,,) = stakingVault.userStakes(msg.sender, stakeId);
        require(amount > 0, "Not the owner of this stake");

        uint256 listingId = nextListingId++;
        listings[listingId] = Listing({
            stakeId: stakeId,
            active: true,
            fulfilled: false,
            seller: msg.sender,
            price: price,
            timestamp: block.timestamp
        });

        emit ListingCreated(listingId, msg.sender, stakeId, price, block.timestamp);
    }

    function cancelListing(uint256 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.seller == msg.sender, "Not the seller of this listing");
        require(listing.active, "Listing is not active");

        listing.active = false;
        emit ListingCancelled(listingId);
    }

    function fulfillListing(uint256 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.active, "Listing is not active");
        require(!listing.fulfilled, "Listing is already fulfilled");

        listing.active = false;
        listing.fulfilled = true;

        uint256 feeAmount = (listing.price * marketplaceFee) / 10_000;
        uint256 sellerAmount = listing.price - feeAmount;

        require(
            paymentToken.transferFrom(msg.sender, address(this), listing.price),
            "Payment transfer failed"
        );

        require(
            paymentToken.transfer(listing.seller, sellerAmount), "Seller payment transfer failed"
        );

        stakingVault.transferStake(listing.seller, msg.sender, listing.stakeId);

        // Swap fee tokens for ETH
        // TODO: Do not sell for eth, instead keep in contract and allow owner to withdraw
        swapTokensForEth(feeAmount);

        emit ListingFulfilled(listingId, msg.sender);
    }

    function updateListingPrice(uint256 listingId, uint256 newPrice) external nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.seller == msg.sender, "Not the seller of this listing");
        require(listing.active, "Listing is not active");

        listing.price = newPrice;
        emit ListingUpdated(listingId, newPrice);
    }

    function updateStakingVault(address _stakingVault) external onlyOwner {
        stakingVault = IStakingVault(_stakingVault);
    }

    function updatePaymentToken(address _paymentToken) external onlyOwner {
        paymentToken = IERC20(_paymentToken);
    }

    // View functions
    function getListing(uint256 listingId)
        external
        view
        returns (address seller, uint256 stakeId, uint256 price, bool active, bool fulfilled)
    {
        Listing memory listing = listings[listingId];
        return (listing.seller, listing.stakeId, listing.price, listing.active, listing.fulfilled);
    }

    function getActiveListings() external view returns (Listing[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < nextListingId; i++) {
            if (listings[i].active) {
                activeCount++;
            }
        }

        Listing[] memory activeListings = new Listing[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < nextListingId; i++) {
            if (listings[i].active) {
                activeListings[index] = listings[i];
                index++;
            }
        }
        return activeListings;
    }

    function getFulfilledListings() external view returns (Listing[] memory) {
        uint256 fulfilledCount = 0;
        for (uint256 i = 0; i < nextListingId; i++) {
            if (listings[i].fulfilled) {
                fulfilledCount++;
            }
        }

        Listing[] memory fulfilledListings = new Listing[](fulfilledCount);
        uint256 index = 0;
        for (uint256 i = 0; i < nextListingId; i++) {
            if (listings[i].fulfilled) {
                fulfilledListings[index] = listings[i];
                index++;
            }
        }
        return fulfilledListings;
    }

    function getListingsBySeller(address seller) external view returns (Listing[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < nextListingId; i++) {
            if (listings[i].seller == seller) {
                count++;
            }
        }

        Listing[] memory sellerListings = new Listing[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < nextListingId; i++) {
            if (listings[i].seller == seller) {
                sellerListings[index] = listings[i];
                index++;
            }
        }
        return sellerListings;
    }

    function swapTokensForEth(uint256 tokenAmount) internal {
        require(paymentToken.approve(address(dexRouter), tokenAmount), "Approve failed");

        address[] memory path = new address[](2);
        path[0] = address(paymentToken);
        path[1] = wethAddress;

        dexRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // Accept any amount of ETH
            path,
            address(this),
            block.timestamp + 15 minutes
        );
    }

    // Function to withdraw accumulated ETH
    function withdrawETH() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");
        (bool success,) = msg.sender.call{value: balance}("");
        require(success, "ETH transfer failed");
    }

    // Function to receive ETH
    receive() external payable {}
}
