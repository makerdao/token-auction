import 'db.sol';
import 'events.sol';
import 'types.sol';
import 'transfer.sol';
import 'util.sol';

contract SplittingAuction is AuctionType
                           , UsingAuctionDatabase
                           , EventfulAuction
                           , TransferUser {
    // Auctionlet bid logic, including transfers.
    function doBid(uint auctionlet_id, address bidder, uint bid_how_much)
        internal
    {
        var a = _auctionlets[auctionlet_id];
        var A = _auctions[a.auction_id];

        // new bidder pays off the old bidder directly. For the first
        // bid this is the seller, so they receive their minimum bid.
        payOffLastBidder(A, a, bidder);

        // if the auctionlet has not been bid on before we need to
        // do some extra accounting
        if (a.base) {
            A.collected += a.buy_amount;
            A.unsold -= a.sell_amount;
            a.base = false;
        }

        if (!A.reversed) {
            var excess_buy = bid_how_much - a.buy_amount;
            A.collected += excess_buy;
        }

        // determine if this bid causes a forward -> reverse transition
        // (only happens in the twoway auction)
        var transition = !A.reversed && (A.collected > A.collection_limit);

        if (transition) {
            // only take excess from the bidder up to the collect target.
            var bid_over_target = A.collected - A.collection_limit;
            A.collected = A.collection_limit;

            settleExcessBuy(A, bidder, excess_buy - bid_over_target);

            // over the target, impute how much less they would have been
            // willing to accept, based on their bid price
            var effective_target_bid = (a.sell_amount * A.collection_limit) / A.sell_amount;
            var reduced_sell_amount = (a.sell_amount * effective_target_bid) / bid_how_much;
            a.buy_amount = bid_how_much - bid_over_target;
            bid_how_much = reduced_sell_amount;
            A.reversed = true;
            AuctionReversal(a.auction_id);
        } else if (!A.reversed) {
            // excess buy token is sent directly from bidder to beneficiary
            settleExcessBuy(A, bidder, excess_buy);
        } else {
            // excess sell token is sent from auction escrow to the beneficiary
            var excess_sell = a.sell_amount - bid_how_much;
            settleExcessSell(A, excess_sell);
            A.sell_amount -= excess_sell;
        }

        // update the bid quantities - new bidder, new bid, same quantity
        newBid(auctionlet_id, bidder, bid_how_much);
        a.last_bid_time = getTime();
    }
    // Auctionlet splitting logic.
    function doSplit(uint auctionlet_id, address splitter,
                      uint bid_how_much, uint quantity)
        internal
        returns (uint new_id, uint split_id)
    {
        var a = _auctionlets[auctionlet_id];

        var (new_quantity, new_bid, split_bid) = _calculate_split(auctionlet_id, quantity);

        // create two new auctionlets and bid on them
        new_id = newAuctionlet(a.auction_id, new_bid, new_quantity,
                               a.last_bidder, a.base);
        split_id = newAuctionlet(a.auction_id, split_bid, quantity,
                                 a.last_bidder, a.base);

        newBid(new_id, a.last_bidder, new_bid);
        doBid(split_id, splitter, bid_how_much);

        deleteAuctionlet(auctionlet_id);
    }
    // Work out how to split a bid into two parts
    function _calculate_split(uint auctionlet_id, uint quantity)
        internal
        returns (uint new_quantity, uint new_bid, uint split_bid)
    {
        var (prev_bid, prev_quantity) = getLastBid(auctionlet_id);
        new_quantity = prev_quantity - quantity;

        // n.b. associativity important because of truncating division
        new_bid = (prev_bid * new_quantity) / prev_quantity;
        split_bid = (prev_bid * quantity) / prev_quantity;
    }
    // Auctionlet claim logic, including transfers.
    function doClaim(uint auctionlet_id) internal {
        var a = _auctionlets[auctionlet_id];
        var A = _auctions[a.auction_id];

        settleBidderClaim(A, a);

        a.unclaimed = false;
        deleteAuctionlet(auctionlet_id);
    }
}

contract AssertiveAuction is Assertive, UsingAuctionDatabase {
    // Check whether an auctionlet is eligible for bidding on
    function assertBiddable(uint auctionlet_id, uint bid_how_much) internal {
        var a = _auctionlets[auctionlet_id];
        var A = _auctions[a.auction_id];

        assert(a.auction_id > 0);  // test for deleted auction
        assert(auctionlet_id > 0);  // test for deleted auctionlet

        // auctionlet must not be expired, unless it is a base
        // auctionlet (has not been bid on since auction creation)
        assert(a.base || !isExpired(auctionlet_id));

        if (A.reversed) {
            // check if reverse biddable
            // bids must decrease the amount of sell token
            assert(bid_how_much <= (a.sell_amount * (100 - A.min_decrease) / 100 ));
        } else {
            // check if forward biddable
            // bids must increase the amount of buy token
            assert(bid_how_much >= (a.buy_amount * (100 + A.min_increase) / 100 ));
        }
    }
    // Check that an auctionlet can be split by the new bid.
    function assertSplittable(uint auctionlet_id, uint bid_how_much, uint quantity) internal {
        var (_, prev_quantity) = getLastBid(auctionlet_id);

        // splits have to reduce the quantity being bid on
        assert(quantity < prev_quantity);

        // splits must have a relative increase in value
        // ('valuation' is the bid scaled up to the full lot)
        var valuation = (bid_how_much * prev_quantity) / quantity;

        assertBiddable(auctionlet_id, valuation);
    }
    // Check whether an auctionlet can be claimed.
    function assertClaimable(uint auctionlet_id) internal {
        var a = _auctionlets[auctionlet_id];
        var A = _auctions[a.auction_id];

        // must be expired
        assert(isExpired(auctionlet_id));
        // must be unclaimed
        assert(a.unclaimed);
    }
}

