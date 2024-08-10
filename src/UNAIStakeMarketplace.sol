// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IStakingVault {
    function transferStake(address from, address to, uint256 poolId, uint256 stakeId) external;
    function stakes(address user, uint256 poolId, uint256 stakeId)
        external
        view
        returns (uint256 amount, uint256 rewardDebt, address owner, uint256 lockEndTime);
}

contract UNAIStakeMarketplace is ReentrancyGuard, Ownable {
    IStakingVault public stakingVault;
    IERC20 public paymentToken;

    struct Listing {
        address seller;
        uint256 poolId;
        uint256 stakeId;
        uint256 price;
        bool active;
    }

    mapping(uint256 => Listing) public listings;
    uint256 public nextListingId;

    event ListingCreated(
        uint256 indexed listingId,
        address indexed seller,
        uint256 poolId,
        uint256 stakeId,
        uint256 price
    );
    event ListingCancelled(uint256 indexed listingId);
    event ListingFulfilled(uint256 indexed listingId, address indexed buyer);

    constructor(address _stakingVault, address _paymentToken) Ownable(msg.sender) {
        stakingVault = IStakingVault(_stakingVault);
        paymentToken = IERC20(_paymentToken);
    }

    function createListing(uint256 poolId, uint256 stakeId, uint256 price) external nonReentrant {
        (,, address owner,) = stakingVault.stakes(msg.sender, poolId, stakeId);
        require(owner == msg.sender, "Not the owner of this stake");

        uint256 listingId = nextListingId++;
        listings[listingId] = Listing({
            seller: msg.sender,
            poolId: poolId,
            stakeId: stakeId,
            price: price,
            active: true
        });

        emit ListingCreated(listingId, msg.sender, poolId, stakeId, price);
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

        listing.active = false;

        require(
            paymentToken.transferFrom(msg.sender, listing.seller, listing.price),
            "Payment transfer failed"
        );

        stakingVault.transferStake(listing.seller, msg.sender, listing.poolId, listing.stakeId);

        emit ListingFulfilled(listingId, msg.sender);
    }

    function updateStakingVault(address _stakingVault) external onlyOwner {
        stakingVault = IStakingVault(_stakingVault);
    }

    function updatePaymentToken(address _paymentToken) external onlyOwner {
        paymentToken = IERC20(_paymentToken);
    }
}
