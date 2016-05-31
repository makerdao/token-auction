import 'erc20/erc20.sol';
import 'auction_manager.sol';


contract EventfulSplitter {
    event Split(uint base_id, uint new_id, uint split_id);
}

// This contract contains a number of Auctions, each of which is
// *splittable*.  The splittable unit of an Auction is an Auctionlet,
// which has all of the Auctions properties but allows for bidding on a
// subset of the full Auction lot.
contract SplitUser is AuctionUser, EventfulSplitter {
    // Place a partial bid on an auctionlet, for less than the full lot.
    // This splits the auctionlet into two, bids on one of the new
    // auctionlets and leaves the other to the previous bidder.
    // The new auctionlet ids are returned, corresponding to the new
    // auctionlets owned by (prev_bidder, new_bidder).
    function bid(uint auctionlet_id, uint bid_how_much, uint quantity)
        returns (uint new_id, uint split_id)
    {
        _assertSplittable(auctionlet_id, bid_how_much, quantity);
        (new_id, split_id) = _doSplit(auctionlet_id, msg.sender, bid_how_much, quantity);
        Split(auctionlet_id, new_id, split_id);
    }
    // Check that an auctionlet can be split by the new bid.
    function _assertSplittable(uint auctionlet_id, uint bid_how_much, uint quantity) internal {
        var a = _auctionlets[auctionlet_id];

        var (_, prev_quantity) = _getLastBid(a);

        // splits have to reduce the quantity being bid on
        assert(quantity < prev_quantity);

        // splits must have a relative increase in value
        // ('valuation' is the bid scaled up to the full lot)
        var valuation = (bid_how_much * prev_quantity) / quantity;

        _assertBiddable(auctionlet_id, valuation);
    }
    // Auctionlet splitting logic.
    function _doSplit(uint auctionlet_id, address splitter,
                      uint bid_how_much, uint quantity)
        internal
        returns (uint new_id, uint split_id)
    {
        var a = _auctionlets[auctionlet_id];

        var (new_quantity, new_bid, split_bid) = _calculate_split(a, quantity);

        // create two new auctionlets and bid on them
        new_id = newAuctionlet(a.auction_id, new_bid, new_quantity,
                               a.last_bidder, a.base);
        split_id = newAuctionlet(a.auction_id, split_bid, quantity,
                                 a.last_bidder, a.base);

        _updateBid(new_id, a.last_bidder, new_bid);
        _doBid(split_id, splitter, bid_how_much);

        delete _auctionlets[auctionlet_id];
    }
    // Work out how to split a bid into two parts
    function _calculate_split(Auctionlet a, uint quantity)
        internal
        returns (uint new_quantity, uint new_bid, uint split_bid)
    {
        var (prev_bid, prev_quantity) = _getLastBid(a);
        new_quantity = prev_quantity - quantity;

        // n.b. associativity important because of truncating division
        new_bid = (prev_bid * new_quantity) / prev_quantity;
        split_bid = (prev_bid * quantity) / prev_quantity;
    }
}

contract SplittableAuctionManager is SplitUser, AuctionManager {}
