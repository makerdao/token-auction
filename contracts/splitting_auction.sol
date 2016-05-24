import 'erc20/erc20.sol';
import 'auction_manager.sol';

// This contract contains a number of Auctions, each of which is
// *splittable*.  The splittable unit of an Auction is an Auctionlet,
// which has all of the Auctions properties but allows for bidding on a
// subset of the full Auction lot.
contract SplittableAuctionManager is AuctionManager {
    // bid on a specific quantity of an auctionlet
    function bid(uint auctionlet_id, uint bid_how_much, uint quantity)
        returns (uint, uint)
    {
        _assertSplittable(auctionlet_id, bid_how_much, quantity);
        return _doSplit(auctionlet_id, bid_how_much, quantity);
    }
    function _assertSplittable(uint auctionlet_id, uint bid_how_much, uint quantity) internal {
        var a = _auctionlets[auctionlet_id];
        var A = _auctions[a.auction_id];

        if (A.reversed) {
            _assertReverseSplittable(auctionlet_id, bid_how_much, quantity);
        } else {
            _assertForwardSplittable(auctionlet_id, bid_how_much, quantity);
        }
    }
    // Check whether an auctionlet is eligible for splitting
    function _assertForwardSplittable(uint auctionlet_id, uint bid_how_much, uint quantity)
        internal
    {
        var a = _auctionlets[auctionlet_id];

        // check that the split actually splits the auctionlet
        // with lower sell_amount
        assert(quantity < a.sell_amount);

        // check that there is a relative increase in value
        // ('valuation' is the bid scaled up to the full lot)
        // n.b avoid dividing by a.buy_amount as it could be zero
        var valuation = (bid_how_much * a.sell_amount) / quantity;

        _assertBiddable(auctionlet_id, valuation);
    }
    function _assertReverseSplittable(uint auctionlet_id, uint bid_how_much, uint quantity)
        internal
    {
        var a = _auctionlets[auctionlet_id];

        assert(quantity < a.buy_amount);

        var valuation = (bid_how_much * a.buy_amount) / quantity;
        _assertBiddable(auctionlet_id, valuation);
    }
    function _doSplit(uint auctionlet_id, uint bid_how_much, uint quantity)
        internal
        returns (uint, uint)
    {
        var a = _auctionlets[auctionlet_id];
        var A = _auctions[a.auction_id];

        uint prev_quantity;
        uint prev_bid;
        if (A.reversed) {
            prev_quantity = a.buy_amount;
            prev_bid = a.sell_amount;
        } else {
            prev_quantity = a.sell_amount;
            prev_bid = a.buy_amount;
        }

        var new_quantity = prev_quantity - quantity;
        //@log previous quantity: `uint prev_quantity`
        //@log modified quantity: `uint new_quantity`
        //@log split quantity:    `uint quantity`

        // n.b. associativity important because of truncating division
        var new_bid = (prev_bid * new_quantity) / prev_quantity;
        //@log previous bid: `uint prev_bid`
        //@log modified bid: `uint new_bid`
        //@log split bid:    `uint bid_how_much`

        if (a.last_bidder != address(this)) {
            var returned_bid = A.buying.transfer(a.last_bidder, a.buy_amount);
            assert(returned_bid);
            A.collected -= a.buy_amount;
        }

        // create two new auctionlets and bid on them
        var new_id = newAuctionlet(a.auction_id, 0, new_quantity);
        var split_id = newAuctionlet(a.auction_id, 0, quantity);

        _doBid(new_id, a.last_bidder, new_bid);
        _doBid(split_id, msg.sender, bid_how_much);

        delete _auctionlets[auctionlet_id];

        return (new_id, split_id);
    }
}
