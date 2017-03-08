pragma solidity ^0.4.0;

import './types.sol';
import './util.sol';

// Methods for transferring funds into and out of the auction manager
// and between bidders and beneficiaries.
//
// Warning: these methods call code outside of the auction, via the
// transfer methods of the buying / selling token. Bear this in mind if
// the auction allows arbitrary tokens to be added, as they could be
// malicious.
//
// These methods take Auction(lets) as arguments to allow them to do
// complex settlement logic. However, their access to the auction is
// read-only - they cannot write to storage.
contract TransferUser is Assertive, MathUser, AuctionType {
    function takeFundsIntoEscrow(Auction auction)
        internal
    {
        assert(auction.selling.transferFrom(auction.creator, this, auction.sell_amount));
    }
    function payOffLastBidder(Auction auction, Auctionlet auctionlet,
                              address new_bidder, address prev_bidder, uint how_much)
        internal
    {
        assert(auction.buying.transferFrom(new_bidder, prev_bidder, how_much));
    }
    function settleExcessBuy(Auction auction, address bidder, uint excess_buy)
        internal
    {
        // if there is only a single beneficiary, they get all of the
        // settlement.
        if (auction.beneficiaries.length == 1) {
            assert(auction.buying.transferFrom(bidder, auction.beneficiaries[0], excess_buy));
            return;
        }

        // If there are multiple beneficiaries, the settlement must be
        // shared out. Each beneficiary has an associated payout, which
        // is the maximum they can receive from the auction. As the
        // auction collects more funds, beneficiaries receive their
        // payouts in turn. The per bid settlement could span multiple
        // payouts - the logic below partitions the settlement as
        // needed.

        // collection state prior to this bid
        var prev_collected = auction.collected - excess_buy;
        // payout transition limits
        var limits = cumsum(auction.payouts);

        for (uint i = 0; i < limits.length; i++) {
            var prev_limit = (i == 0) ? 0 : limits[i - 1];
            if (prev_limit > auction.collected) break;

            var limit = limits[i];
            if (limit < prev_collected) continue;

            var payout = excess_buy
                       - zeroSub(prev_limit, prev_collected)
                       - zeroSub(auction.collected, limit);

            assert(auction.buying.transferFrom(bidder, auction.beneficiaries[i], payout));
        }
    }
    function settleExcessSell(Auction auction, uint excess_sell)
        internal
    {
        assert(auction.selling.transfer(auction.refund, excess_sell));
    }
    function settleBidderClaim(Auction auction, Auctionlet auctionlet)
        internal
    {
        assert(auction.selling.transfer(auctionlet.last_bidder, auctionlet.sell_amount));
    }
    function settleReclaim(Auction auction)
        internal
    {
        assert(auction.selling.transfer(auction.creator, auction.unsold));
    }
}

