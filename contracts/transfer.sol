import 'types.sol';
import 'util.sol';

contract TransferUser is Assertive, MathUser, AuctionType {
    function takeFundsIntoEscrow(Auction A) internal {
        assert(A.selling.transferFrom(A.creator, this, A.sell_amount));
    }
    function payOffLastBidder(Auction A, Auctionlet a, address bidder) internal {
        assert(A.buying.transferFrom(bidder, a.last_bidder, a.buy_amount));
    }
    function settleExcessBuy(Auction A, address bidder, uint excess_buy) internal {
        if (A.beneficiaries.length == 1) {
            assert(A.buying.transferFrom(bidder, A.beneficiaries[0], excess_buy));
            return;
        }

        var prev_collected = A.collected - excess_buy;

        var limits = cumsum(A.payouts);

        for (uint i = 0; i < limits.length; i++) {
            var prev_limit = (i == 0) ? 0 : limits[i - 1];
            if (prev_limit > A.collected) break;

            var limit = limits[i];
            if (limit < prev_collected) continue;

            var payout = excess_buy
                       - flat(prev_limit, prev_collected)
                       - flat(A.collected, limit);

            assert(A.buying.transferFrom(bidder, A.beneficiaries[i], payout));
        }
    }
    function settleExcessSell(Auction A, uint excess_sell) internal {
        assert(A.selling.transfer(A.refund, excess_sell));
    }
    function settleBidderClaim(Auction A, Auctionlet a) internal {
        assert(A.selling.transfer(a.last_bidder, a.sell_amount));
    }
    function settleReclaim(Auction A) internal {
        assert(A.selling.transfer(A.creator, A.unsold));
    }
}

