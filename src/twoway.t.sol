pragma solidity ^0.4.15;

import './base.t.sol';

contract TwoWayTest is AuctionTest {
    function newTwoWayAuction() returns (uint, uint) {
        return manager.newTwoWayAuction( seller    // beneficiary
                                       , t1        // selling
                                       , t2        // buying
                                       , 100 * T1  // sell_amount
                                       , 10 * T2   // start_bid
                                       , 1         // min_increase (%)
                                       , 1         // min_decrease (%)
                                       , 1 years   // ttl
                                       , 100 * T2  // collection_limit
                                       );
    }
    function testReversalEvent() {
        var (id, base) = newTwoWayAuction();
        bidder1.doBid(base, 101 * T2);

        expectEventsExact(manager);
        LogNewAuction(id, base);
        LogAuctionReversal(id);
        LogBid(base);
    }
    function testNewTwoWayAuction() {
        var (id, base) = newTwoWayAuction();
        assertEq(manager.getCollectMax(id), 100 * T2);
    }
    function testBidEqualTargetNoReversal() {
        // bids at the target should not cause the auction to reverse
        var (id, base) = newTwoWayAuction();
        bidder1.doBid(base, 100 * T2);
        assert(!manager.isReversed(id));
    }
    function testBidOverTargetReversal() {
        // bids over the target should cause the auction to reverse
        var (id, base) = newTwoWayAuction();
        bidder1.doBid(base, 101 * T2);
        assert(manager.isReversed(id));
    }
    function testBidOverTargetRefundsDifference() {
        var (id, base) = newTwoWayAuction();
        var t2_balance_before = t2.balanceOf(bidder1);
        bidder1.doBid(base, 110 * T2);
        var t2_balance_after = t2.balanceOf(bidder1);

        var balance_diff = t2_balance_before - t2_balance_after;
        assertEq(balance_diff, 100 * T2);
    }
    function testBidOverTargetSetsReverseBidder() {
        var (id, base) = newTwoWayAuction();
        bidder1.doBid(base, 110 * T2);

        var (auction_id, last_bidder,
             buy_amount, sell_amount) = manager.getAuctionlet(base);

        assertEq(last_bidder, bidder1);
    }
    function testBidOverTargetSetsReverseBuyAmount() {
        var (id, base) = newTwoWayAuction();
        bidder1.doBid(base, 110 * T2);

        var (auction_id, last_bidder,
             buy_amount, sell_amount) = manager.getAuctionlet(base);

        assertEq(buy_amount, 100 * T2);
    }
    function testBidOverTargetSetsReverseBid() {
        var (id, base) = newTwoWayAuction();
        bidder1.doBid(base, 110 * T2);

        var (auction_id, last_bidder,
             buy_amount, sell_amount) = manager.getAuctionlet(base);

        // as the bidder has bid over the target, we use their surplus
        // valuation to decrease the sell_amount that they will receive.
        //
        // This amount is calculated as q^2 * B / (b * Q), where q is
        // the auctionlet sell_amount, Q is the total auction sell_amount,
        // B is the target and b is the given bid. In an auction with no
        // splitting, q = Q and this simplifies to Q * B / b
        var expected_sell_amount = (100 * T1 * 100 * T2) / (110 * T2);
        assertEq(sell_amount, expected_sell_amount);
    }
    function testBaseSplitEqualTargetNoReversal() {
        var (id, base) = newTwoWayAuction();
        bidder1.doBid(base, 100 * T2, 60 * T1);
        assert(!manager.isReversed(id));
    }
    function testBaseSplitOverTargetReversal() {
        var (id, base) = newTwoWayAuction();
        bidder1.doBid(base, 110 * T2, 60 * T1);
        assert(manager.isReversed(id));
    }
    function testBaseSplitOverTargetRefundsDifference() {
        var (id, base) = newTwoWayAuction();
        var t2_balance_before = t2.balanceOf(bidder1);
        bidder1.doBid(base, 120 * T2, 60 * T1);
        var t2_balance_after = t2.balanceOf(bidder1);

        var balance_diff = t2_balance_before - t2_balance_after;
        assertEq(balance_diff, 100 * T2);
    }
    function testBaseSplitOverTargetSetsReverseBidder() {
        var (id, base) = newTwoWayAuction();
        var (nid, sid) = bidder1.doBid(base, 120 * T2, 50 * T1);

        var (auction_id, last_bidder,
             buy_amount, sell_amount) = manager.getAuctionlet(sid);

        assertEq(last_bidder, bidder1);
    }
    function testBaseSplitOverTargetSetsReverseBuyAmount() {
        var (id, base) = newTwoWayAuction();
        var (nid, sid) = bidder1.doBid(base, 120 * T2, 50 * T1);

        var (auction_id, last_bidder,
             buy_amount, sell_amount) = manager.getAuctionlet(sid);

        assertEq(buy_amount, 100 * T2);
    }
    function testBaseSplitOverTargetSetsReverseBid() {
        var (id, base) = newTwoWayAuction();
        var (nid, sid) = bidder1.doBid(base, 120 * T2, 50 * T1);

        var (auction_id, last_bidder,
             buy_amount, sell_amount) = manager.getAuctionlet(sid);

        // as the bidder has bid over the target, we use their surplus
        // valuation to decrease the sell_amount that they will receive.
        //
        // This amount is calculated as q^2 * B / (b * Q), where q is
        // the auctionlet sell_amount, Q is the total auction sell_amount,
        // B is the target and b is the given bid.
        var expected_sell_amount = (50 * T1 * 50 * T1 * 100 * T2) / (120 * T2 * 100 * T1);
        assertEq(sell_amount, expected_sell_amount);
    }
}

// two-way auction with given refund address
contract TwoWayRefundTest is AuctionTest {
    function newTwoWayAuction() returns (uint auction_id, uint base_id) {
        (auction_id, base_id) = manager.newTwoWayAuction( seller        // beneficiary
                                                        , beneficiary1  // refund
                                                        , t1            // selling
                                                        , t2            // buying
                                                        , 100 * T1      // sell_amount
                                                        , 10 * T2       // start_bid
                                                        , 1             // min_increase (%)
                                                        , 1             // min_decrease (%)
                                                        , 1 years       // ttl
                                                        , 100 * T2      // collection_limit
                                                        );
    }
    function testNewTwoWayAuction() {
        var (id, base) = newTwoWayAuction();
        assertEq(manager.getRefundAddress(id), beneficiary1);
    }
    function testBidTransfersRefund() {
        // successive bids in the reverse part of the auction should
        // refund the `refund` address
        var (id, base) = newTwoWayAuction();

        bidder1.doBid(base, 101 * T2);
        bidder1.doBid(base, 90 * T1);

        var balance_before = t1.balanceOf(beneficiary1);
        bidder2.doBid(base, 80 * T1);
        var balance_after = t1.balanceOf(beneficiary1);

        assertEq(balance_after - balance_before, 10 * T1);
    }
    function testBidNoTransferToCreator() {
        // successive bids in the reverse part of the auction should
        // send nothing to the creator
        var (id, base) = newTwoWayAuction();

        bidder1.doBid(base, 101 * T2);
        bidder1.doBid(base, 90 * T1);

        var balance_before = t1.balanceOf(this);
        bidder2.doBid(base, 80 * T1);
        var balance_after = t1.balanceOf(this);

        assertEq(balance_after, balance_before);
    }
    function testBidNoTransferToBeneficiary() {
        // successive bids in the reverse part of the auction should
        // send nothing to the given beneficiary
        var (id, base) = newTwoWayAuction();

        bidder1.doBid(base, 101 * T2);
        bidder1.doBid(base, 90 * T1);

        var balance_before = t1.balanceOf(seller);
        bidder2.doBid(base, 80 * T1);
        var balance_after = t1.balanceOf(seller);

        assertEq(balance_after, balance_before);
    }
}
