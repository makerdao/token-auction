pragma solidity ^0.4.15;

import './db.sol';
import './events.sol';
import './types.sol';

contract TwoWayAuction is AuctionDatabaseUser
                        , EventfulAuction
{
    // Auctionlet bid logic, including transfers.
    function doBid(uint auctionlet_id, address new_bidder, uint bid_how_much)
        internal
    {
        var auctionlet = auctionlets(auctionlet_id);
        var auction = auctions(auctionlet.auction_id);

        // if the auctionlet has not been bid on before we need to
        // do some extra accounting
        if (auctionlet.base) {
            auction.collected += auctionlet.buy_amount;
            auction.unsold -= auctionlet.sell_amount;
            auctionlet.base = false;
        }

        // new bidder pays off the old bidder directly. For the first
        // bid this is the seller, so they receive their minimum bid.
        assert(auction.buying.transferFrom(new_bidder, auctionlet.last_bidder, auctionlet.buy_amount));

        if (auction.reversed) {
            var excess_sell = sub(auctionlet.sell_amount, bid_how_much);

            auctionlet.sell_amount = bid_how_much;  // reverse bids compete on sell token

            // new bidder pays off the old bidder directly. For the first
            // bid this is the buyer, so they receive their buy amount.
            // excess sell token is sent from auction escrow to the refund address
            assert(auction.selling.transfer(auction.refund, excess_sell));

        } else {
            var excess_buy = sub(bid_how_much, auctionlet.buy_amount);

            // Forward auctions increment the total auction collection on
            // each bid. In reverse auctions this is unchanged per bid as
            // bids compete on the sell side.
            auction.collected += excess_buy;

            if (auction.collected > auction.collection_limit) {
                // only take excess from the bidder up to the collect target.
                var bid_over_target = sub(auction.collected, auction.collection_limit);

                // over the target, infer how much less they would have been
                // willing to accept, based on their bid price
                var effective_target_bid = mul(auctionlet.sell_amount, auction.collection_limit) / auction.sell_amount;
                var inferred_reverse_bid = mul(auctionlet.sell_amount, effective_target_bid) / bid_how_much;

                auction.collected = auction.collection_limit;

                // reverse bids compete on sell token.
                auctionlet.sell_amount = inferred_reverse_bid;
                auction.reversed = true;

                // excess buy token (up to the target) is sent directly
                // from bidder to beneficiary
                excess_buy = sub(excess_buy, bid_over_target);
                bid_how_much = sub(bid_how_much, bid_over_target);
            }

            auctionlet.buy_amount = bid_how_much;  // forward bids compete on buy token

            require(auction.buying.transferFrom(new_bidder, auction.beneficiary, excess_buy));
        }
        auctionlet.last_bidder = new_bidder;
        auctionlet.last_bid_time = getTime();
    }
    // Auctionlet claim logic, including transfers.
    function doClaim(uint auctionlet_id)
        internal
    {
        AuctionType.Auctionlet auctionlet = auctionlets(auctionlet_id);
        AuctionType.Auction auction = auctions(auctionlet.auction_id);

        auctionlet.unclaimed = false;
        assert(auction.selling.transfer(auctionlet.last_bidder, auctionlet.sell_amount));
    }
}

contract SplittingAuction is TwoWayAuction {
    // Auctionlet splitting logic.
    function doSplit(uint auctionlet_id, address splitter,
                     uint bid_how_much, uint quantity)
        internal
        returns (uint new_id, uint split_id)
    {
        var auctionlet = auctionlets(auctionlet_id);

        var (new_quantity, new_bid, split_bid) = _calculate_split(auctionlet_id, quantity);

        // modify the old auctionlet
        setLastBid(auctionlet_id, new_bid, new_quantity);
        new_id = auctionlet_id;

        // create a new auctionlet with the split quantity
        split_id = newAuctionlet(auctionlet.auction_id, split_bid, quantity,
                                 auctionlet.last_bidder, auctionlet.base);
        doBid(split_id, splitter, bid_how_much);
    }
    // Work out how to split a bid into two parts
    function _calculate_split(uint auctionlet_id, uint quantity)
        private
        returns (uint new_quantity, uint new_bid, uint split_bid)
    {
        var (prev_bid, prev_quantity) = getLastBid(auctionlet_id);
        new_quantity = sub(prev_quantity, quantity);

        // n.b. associativity important because of truncating division
        new_bid = mul(prev_bid, new_quantity) / prev_quantity;
        split_bid = mul(prev_bid, quantity) / prev_quantity;
    }
}

contract AssertiveAuction is Assertive, AuctionDatabaseUser {
    // Check whether an auctionlet is eligible for bidding on
    function assertBiddable(uint auctionlet_id, uint bid_how_much)
        internal
    {
        var auctionlet = auctionlets(auctionlet_id);
        var auction = auctions(auctionlet.auction_id);

        // auctionlet must not be expired
        // (N.B. base auctionlets never expire)
        assert(!isExpired(auctionlet_id));
        // must be unclaimed
        assert(auctionlet.unclaimed);

        if (auction.reversed) {
            // check if reverse biddable
            // bids strictly decrease the amount of sell token
            assert(bid_how_much < auctionlet.sell_amount);
            // bids must decrease by at least the minimum decrease (%)
            var max_bid = mul(auctionlet.sell_amount, 100 - auction.min_decrease) / 100;
            assert(bid_how_much <= max_bid);
        } else {
            // check if forward biddable
            // bids strictly increase the amount of buy token
            assert(bid_how_much > auctionlet.buy_amount);
            // bids must increase by at least the minimum increase (%)
            var min_bid = mul(auctionlet.buy_amount, 100 + auction.min_increase) / 100;
            assert(bid_how_much >= min_bid);
        }
    }
    // Check that an auctionlet can be split by the new bid.
    function assertSplittable(uint auctionlet_id, uint bid_how_much, uint quantity)
        internal
    {
        var (_, prev_quantity) = getLastBid(auctionlet_id);

        // splits have to reduce the quantity being bid on
        assert(quantity < prev_quantity);

        // splits must have a relative increase in value
        // ('valuation' is the bid scaled up to the full lot)
        var valuation = mul(bid_how_much, prev_quantity) / quantity;

        assertBiddable(auctionlet_id, valuation);
    }
    // Check whether an auctionlet can be claimed.
    function assertClaimable(uint auctionlet_id)
        internal
    {
        var auctionlet = auctionlets(auctionlet_id);
        var auction = auctions(auctionlet.auction_id);

        // must be expired
        assert(isExpired(auctionlet_id));
        // must be unclaimed
        assert(auctionlet.unclaimed);
    }
}

contract AuctionFrontend is AuctionFrontendType
                          , EventfulAuction
                          , AssertiveAuction
                          , TwoWayAuction
                          , MutexUser
{
    // Place a new bid on a specific auctionlet.
    function bid(uint auctionlet_id, uint bid_how_much)
        exclusive
    {
        assertBiddable(auctionlet_id, bid_how_much);
        doBid(auctionlet_id, msg.sender, bid_how_much);
        LogBid(auctionlet_id);
    }
    // Allow parties to an auction to claim their take.
    // If the auction has expired, individual auctionlet high bidders
    // can claim their winnings.
    function claim(uint auctionlet_id)
        exclusive
    {
        assertClaimable(auctionlet_id);
        doClaim(auctionlet_id);
    }
}


contract SplittingAuctionFrontend is SplittingAuctionFrontendType
                                   , EventfulAuction
                                   , AssertiveAuction
                                   , SplittingAuction
                                   , MutexUser
{
    // Place a partial bid on an auctionlet, for less than the full lot.
    // This splits the auctionlet into two, bids on one of the new
    // auctionlets and leaves the other to the previous bidder.
    // The new auctionlet ids are returned, corresponding to the new
    // auctionlets owned by (prev_bidder, new_bidder).
    function bid(uint auctionlet_id, uint bid_how_much, uint quantity)
        exclusive
        returns (uint new_id, uint split_id)
    {
        var (, prev_quantity) = getLastBid(auctionlet_id);
        if (quantity == prev_quantity) {
            assertBiddable(auctionlet_id, bid_how_much);
            doBid(auctionlet_id, msg.sender, bid_how_much);
            new_id = auctionlet_id;
            LogBid(auctionlet_id);
        } else {
            assertSplittable(auctionlet_id, bid_how_much, quantity);
            (new_id, split_id) = doSplit(auctionlet_id, msg.sender, bid_how_much, quantity);
            LogSplit(auctionlet_id, new_id, split_id);
        }
    }
    // Allow parties to an auction to claim their take.
    // If the auction has expired, individual auctionlet high bidders
    // can claim their winnings.
    function claim(uint auctionlet_id) {
        assertClaimable(auctionlet_id);
        doClaim(auctionlet_id);
    }
}

