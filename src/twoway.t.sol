pragma solidity ^0.4.15;

import './base.t.sol';

contract TwoWayTest is AuctionTest {
    function newTwoWayAuction() public returns (uint, uint) {
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
    function testReversalEvent() public {
        var (id, base) = newTwoWayAuction();
        bidder1.doBid(base, 101 * T2, false);

        expectEventsExact(manager);
        LogNewAuction(id, base);
        LogAuctionReversal(id);
        LogBid(base);
    }
    function testNewTwoWayAuction() public {
        var (id, ) = newTwoWayAuction();
        assertEq(manager.getCollectMax(id), 100 * T2);
    }
    function testBidEqualTargetNoReversal() public {
        // bids at the target should not cause the auction to reverse
        var (id, base) = newTwoWayAuction();
        bidder1.doBid(base, 100 * T2, false);
        assert(!manager.isReversed(id));
    }
    function testBidOverTargetReversal() public {
        // bids over the target should cause the auction to reverse
        var (id, base) = newTwoWayAuction();
        bidder1.doBid(base, 101 * T2, false);
        assert(manager.isReversed(id));
    }
    function testBidOverTargetRefundsDifference() public {
        var (, base) = newTwoWayAuction();
        var t2_balance_before = t2.balanceOf(bidder1);
        bidder1.doBid(base, 110 * T2, false);
        var t2_balance_after = t2.balanceOf(bidder1);

        var balance_diff = t2_balance_before - t2_balance_after;
        assertEq(balance_diff, 100 * T2);
    }
    function testBidOverTargetSetsReverseBidder() public {
        var (, base) = newTwoWayAuction();
        bidder1.doBid(base, 110 * T2, false);

        var (, last_bidder, , ) = manager.getAuctionlet(base);

        assertEq(last_bidder, bidder1);
    }
    function testBidOverTargetSetsReverseBuyAmount() public {
        var (, base) = newTwoWayAuction();
        bidder1.doBid(base, 110 * T2, false);

        var (, , buy_amount, ) = manager.getAuctionlet(base);

        assertEq(buy_amount, 100 * T2);
    }
    function testBidOverTargetSetsReverseBid() public {
        var (, base) = newTwoWayAuction();
        bidder1.doBid(base, 110 * T2, false);

        var (, , , sell_amount) = manager.getAuctionlet(base);

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
    function testBaseSplitEqualTargetNoReversal() public {
        var (id, base) = newTwoWayAuction();
        bidder1.doBid(base, 100 * T2, 60 * T1, false);
        assert(!manager.isReversed(id));
    }
    function testBaseSplitOverTargetReversal() public {
        var (id, base) = newTwoWayAuction();
        bidder1.doBid(base, 110 * T2, 60 * T1, false);
        assert(manager.isReversed(id));
    }
    function testBaseSplitOverTargetRefundsDifference() public {
        var (, base) = newTwoWayAuction();
        var t2_balance_before = t2.balanceOf(bidder1);
        bidder1.doBid(base, 120 * T2, 60 * T1, false);
        var t2_balance_after = t2.balanceOf(bidder1);

        var balance_diff = t2_balance_before - t2_balance_after;
        assertEq(balance_diff, 100 * T2);
    }
    function testBaseSplitOverTargetSetsReverseBidder() public {
        var (, base) = newTwoWayAuction();
        var (, sid) = bidder1.doBid(base, 120 * T2, 50 * T1, false);

        var (, last_bidder, , ) = manager.getAuctionlet(sid);

        assertEq(last_bidder, bidder1);
    }
    function testBaseSplitOverTargetSetsReverseBuyAmount() public {
        var (, base) = newTwoWayAuction();
        var (, sid) = bidder1.doBid(base, 120 * T2, 50 * T1, false);

        var (, , buy_amount, ) = manager.getAuctionlet(sid);

        assertEq(buy_amount, 100 * T2);
    }
    function testBaseSplitOverTargetSetsReverseBid() public {
        var (, base) = newTwoWayAuction();
        var (, sid) = bidder1.doBid(base, 120 * T2, 50 * T1, false);

        var (, , , sell_amount) = manager.getAuctionlet(sid);

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
    function newTwoWayAuction() public returns (uint auction_id, uint base_id) {
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
    function testNewTwoWayAuction() public {
        var (id, ) = newTwoWayAuction();
        assertEq(manager.getRefundAddress(id), beneficiary1);
    }
    function testBidTransfersRefund() public {
        // successive bids in the reverse part of the auction should
        // refund the `refund` address
        var (, base) = newTwoWayAuction();

        bidder1.doBid(base, 101 * T2, false);
        bidder1.doBid(base, 90 * T1, true);

        var balance_before = t1.balanceOf(beneficiary1);
        bidder2.doBid(base, 80 * T1, true);
        var balance_after = t1.balanceOf(beneficiary1);

        assertEq(balance_after - balance_before, 10 * T1);
    }
    function testBidNoTransferToCreator() public {
        // successive bids in the reverse part of the auction should
        // send nothing to the creator
        var (, base) = newTwoWayAuction();

        bidder1.doBid(base, 101 * T2, false);
        bidder1.doBid(base, 90 * T1, true);

        var balance_before = t1.balanceOf(this);
        bidder2.doBid(base, 80 * T1, true);
        var balance_after = t1.balanceOf(this);

        assertEq(balance_after, balance_before);
    }
    function testBidNoTransferToBeneficiary() public {
        // successive bids in the reverse part of the auction should
        // send nothing to the given beneficiary
        var (, base) = newTwoWayAuction();

        bidder1.doBid(base, 101 * T2, false);
        bidder1.doBid(base, 90 * T1, true);

        var balance_before = t1.balanceOf(seller);
        bidder2.doBid(base, 80 * T1, true);
        var balance_after = t1.balanceOf(seller);

        assertEq(balance_after, balance_before);
    }
}
