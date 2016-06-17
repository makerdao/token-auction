import 'types.sol';
import 'util.sol';

contract AuctionDatabase is AuctionType, UsingTime {
    mapping(uint => Auction) _auctions;
    uint _last_auction_id;

    mapping(uint => Auctionlet) _auctionlets;
    uint _last_auctionlet_id;

    function createAuctionlet(Auctionlet a) internal returns (uint id) {
        id = ++_last_auctionlet_id;
        _auctionlets[id] = a;
    }
    function createAuction(Auction A) internal returns (uint id) {
        id = ++_last_auction_id;
        _auctions[id] = A;
    }
    function newAuctionlet(uint auction_id, uint bid,
                           uint quantity, address last_bidder, bool base)
        internal returns (uint auctionlet_id)
    {
        Auctionlet memory auctionlet;
        auctionlet.auction_id = auction_id;
        auctionlet.unclaimed = true;
        auctionlet.last_bidder = last_bidder;
        auctionlet.base = base;
        auctionlet.last_bid_time = getTime();

        auctionlet_id = createAuctionlet(auctionlet);

        setLastBid(auctionlet_id, bid, quantity);
    }
    function setReversed(uint auction_id, bool reversed) internal {
        _auctions[auction_id].reversed = reversed;
    }
    // check if an auction is reversed
    function isReversed(uint auction_id) constant returns (bool reversed) {
        return _auctions[auction_id].reversed;
    }
    // check if an auctionlet is expired
    function isExpired(uint auctionlet_id) constant returns (bool expired) {
        var a = _auctionlets[auctionlet_id];
        var A = _auctions[a.auction_id];
        expired = (getTime() - a.last_bid_time) > A.duration;
    }
    function getRefundAddress(uint auction_id) returns (address) {
        return _auctions[auction_id].refund;
    }
    function setRefundAddress(uint auction_id, address refund)
        only_creator(auction_id)
    {
        var A = _auctions[auction_id];
        A.refund = refund;
    }
    modifier only_creator(uint auction_id) {
        if (msg.sender != _auctions[auction_id].creator)
            throw;
        _
    }
    // Auctionlet bid update logic.
    function newBid(uint auctionlet_id, address bidder, uint bid_how_much) {
        var a = _auctionlets[auctionlet_id];
        var A = _auctions[a.auction_id];

        var quantity = A.reversed ? a.buy_amount : a.sell_amount;

        setLastBid(auctionlet_id, bid_how_much, quantity);
        a.last_bidder = bidder;
    }
    function getLastBid(uint auctionlet_id)
        internal
        constant
        returns (uint prev_bid, uint prev_quantity)
    {
        var a = _auctionlets[auctionlet_id];
        var A = _auctions[a.auction_id];

        if (A.reversed) {
            prev_bid = a.sell_amount;
            prev_quantity = a.buy_amount;
        } else {
            prev_bid = a.buy_amount;
            prev_quantity = a.sell_amount;
        }
    }
    function setLastBid(uint auctionlet_id, uint bid, uint quantity)
        internal
    {
        var a = _auctionlets[auctionlet_id];
        var A = _auctions[a.auction_id];

        if (A.reversed) {
            a.sell_amount = bid;
            a.buy_amount = quantity;
        } else {
            a.sell_amount = quantity;
            a.buy_amount = bid;
        }
    }
}
