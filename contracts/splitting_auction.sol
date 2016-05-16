import 'erc20/erc20.sol';

import 'assertive.sol';

// This contract contains a number of Auctions, each of which is
// *splittable*.  The splittable unit of an Auction is an Auctionlet,
// which has all of the Auctions properties but allows for bidding on a
// subset of the full Auction lot.
contract SplittableAuctionManager is Assertive {
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

    mapping(uint => Auction) _auctions;
    uint _last_auction_id;

    mapping(uint => Auctionlet) _auctionlets;
    uint _last_auctionlet_id;

    // Create a new auction, with specific parameters.
    // Bidding is done through the auctions associated auctionlets,
    // of which there is one initially.
    function newAuction( address beneficiary
                        , ERC20 selling
                        , ERC20 buying
                        , uint sell_amount
                        , uint min_bid
                        , uint min_increase
                        )
        returns (uint auction_id)
    {
        Auction memory a;
        a.beneficiary = beneficiary;
        a.selling = selling;
        a.buying = buying;
        a.sell_amount = sell_amount;
        a.min_bid = min_bid;
        a.min_increase = min_increase;

        _auctions[++_last_auction_id] = a;

        Auctionlet memory base_auctionlet;
        base_auctionlet.auction_id = _last_auction_id;
        base_auctionlet.quantity = sell_amount;

        _auctionlets[++_last_auctionlet_id] = base_auctionlet;

        return _last_auction_id;
    }
    function getAuction(uint id) constant
        returns (address, ERC20, ERC20, uint, uint, uint)
    {
        Auction a = _auctions[id];
        return (a.beneficiary, a.selling, a.buying,
                a.sell_amount, a.min_bid, a.min_increase);
    }
    function getAuctionlet(uint id) constant
        returns (uint, address, uint, uint)
    {
        Auctionlet a = _auctionlets[id];
        return (a.auction_id, a.last_bidder, a.last_bid, a.quantity);
    }
    // bid on a specifc auctionlet
    function bid(uint auctionlet_id, uint bid_how_much) {
        var a = _auctionlets[auctionlet_id];
        var A = _auctions[a.auction_id];
        assert(bid_how_much >= A.min_bid);
        assert(bid_how_much > (a.last_bid + A.min_increase));
    }
    // bid on a specific quantity of an auctionlet
    function split(uint auctionlet_id, uint quantity, uint bid_how_much) {}
    // claim the existing bids from all auctionlets connected to a
    // specific auction
    function claim(uint auction_id) {}
}
