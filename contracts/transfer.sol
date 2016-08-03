import 'types.sol';
import 'util.sol';

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
    function takeFundsIntoEscrow(Auction A)
        internal
    {
        assert(A.selling.transferFrom(A.creator, this, A.sell_amount));
    }
    function payOffLastBidder(Auction A, Auctionlet a,
                              address new_bidder, address prev_bidder, uint how_much)
        internal
    {
        assert(A.buying.transferFrom(new_bidder, prev_bidder, how_much));
    }
    function settleExcessBuy(Auction A, address bidder, uint excess_buy)
        internal
    {
        // if there is only a single beneficiary, they get all of the
        // settlement.
        if (A.beneficiaries.length == 1) {
            assert(A.buying.transferFrom(bidder, A.beneficiaries[0], excess_buy));
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
        var prev_collected = A.collected - excess_buy;
        // payout transition limits
        var limits = cumsum(A.payouts);

        for (uint i = 0; i < limits.length; i++) {
            var prev_limit = (i == 0) ? 0 : limits[i - 1];
            if (prev_limit > A.collected) break;

            var limit = limits[i];
            if (limit < prev_collected) continue;

            var payout = excess_buy
                       - zeroSub(prev_limit, prev_collected)
                       - zeroSub(A.collected, limit);

            assert(A.buying.transferFrom(bidder, A.beneficiaries[i], payout));
        }
    }
    function settleExcessSell(Auction A, uint excess_sell)
        internal
    {
        assert(A.selling.transfer(A.refund, excess_sell));
    }
    function settleBidderClaim(Auction A, Auctionlet a)
        internal
    {
        assert(A.selling.transfer(a.last_bidder, a.sell_amount));
    }
    function settleReclaim(Auction A)
        internal
    {
        assert(A.selling.transfer(A.creator, A.unsold));
    }
}

