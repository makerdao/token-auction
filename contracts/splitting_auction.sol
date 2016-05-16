import 'erc20/erc20.sol';

// This contract contains a number of Auctions, each of which is
// *splittable*.  The splittable unit of an Auction is an Auctionlet,
// which has all of the Auctions properties but allows for bidding on a
// subset of the full Auction lot.
contract SplittableAuctionManager {
    struct Auction {
        address beneficiary;
        ERC20 selling;
        ERC20 buying;
        uint min_bid;
        uint min_increase;
        uint sell_amount;
        uint claimable;
        uint claimed;
    }
    struct Auctionlet {
        uint     auction_id;
        address  last_bidder;
        uint     last_bid;
        uint     quantity;
    }
    function newAuction( address beneficiary
                        , ERC20 selling
                        , ERC20 buying
                        , uint sell_amount
                        , uint min_bid
                        , uint min_increase
                        )
        returns (uint auction_id) {}
    // bid on a specifc auctionlet
    function bid(uint auctionlet_id, uint bid_how_much) {}
    // bid on a specific quantity of an auctionlet
    function split(uint auctionlet_id, uint quantity, uint bid_how_much) {}
    // claim the existing bids from all auctionlets connected to a
    // specific auction
    function claim(uint auction_id) {}
}
