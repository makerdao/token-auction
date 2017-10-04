pragma solidity ^0.4.15;

import './base.t.sol';

contract ForwardSplittingTest is AuctionTest
{
    function newAuction() public returns (uint, uint) {
        return manager.newAuction( seller    // beneficiary
                                 , t1        // selling
                                 , t2        // buying
                                 , 100 * T1  // sell_amount
                                 , 10 * T2   // start_bid
                                 , 1         // min_increase (%)
                                 , 1 years   // ttl
                                 );
    }
    function testSplitEvent() public {
        var (id, base) = newAuction();

        var (nid1, sid1) = bidder1.doBid(base, 5 * T2, 40 * T1, false);
        var (nid2, sid2) = bidder2.doBid(nid1, 6 * T2, 40 * T1, false);
        var (nid3, sid3) = bidder1.doBid(sid1, 6 * T2, 30 * T1, false);

        expectEventsExact(manager);
        LogNewAuction(id, base);
        LogSplit(base, nid1, sid1);
        LogSplit(nid1, nid2, sid2);
        LogSplit(sid1, nid3, sid3);
    }
    function testSplitBase() public {
        var (, base) = newAuction();

        var (auction_id0, last_bidder0,
             buy_amount0, sell_amount0) = manager.getAuctionlet(base);

        var (nid, ) = bidder1.doBid(base, 5 * T2, 40 * T1, false);

        var (auction_id1, last_bidder1,
             buy_amount1, sell_amount1) = manager.getAuctionlet(nid);

        var expected_new_bid = 6 * T2;
        var expected_new_sell_amount = 60 * T1;

        assertEq(auction_id0, auction_id1);
        assertEq(last_bidder0, seller);
        assertEq(last_bidder1, seller);

        assertEq(buy_amount0, 10 * T2);
        assertEq(sell_amount0, 100 * T1);

        assertEq(buy_amount1, expected_new_bid);
        assertEq(sell_amount1, expected_new_sell_amount);
    }
    function testSplitTransfersFromBidder() public {
        var (, base) = newAuction();

        var balance_before = t2.balanceOf(bidder1);
        bidder1.doBid(base, 7 * T2, 60 * T1, false);
        var balance_after = t2.balanceOf(bidder1);

        assertEq(balance_before - balance_after, 7 * T2);
    }
    function testSplitBaseTransfersToSeller() public {
        var (, base) = newAuction();

        var balance_before = t2.balanceOf(seller);
        bidder1.doBid(base, 7 * T2, 60 * T1, false);
        var balance_after = t2.balanceOf(seller);

        assertEq(balance_after - balance_before, 7 * T2);
    }
    function testSplitTransfersToPrevBidder() public {
        var (, base) = newAuction();

        bidder1.doBid(base, 20 * T2, false);

        var balance_before = t2.balanceOf(bidder1);
        bidder2.doBid(base, 20 * T2, 50 * T1, false);
        var balance_after = t2.balanceOf(bidder1);

        assertEq(balance_after - balance_before, 10 * T2);
    }
    function testAnotherSplitTransfersToPrevSplitter() public {
        var (, base) = newAuction();

        var (, sid) = bidder1.doBid(base, 20 * T2, 80 * T1, false);

        var balance_before = t2.balanceOf(bidder1);
        bidder2.doBid(sid, 20 * T2, 40 * T1, false);
        var balance_after = t2.balanceOf(bidder1);

        assertEq(balance_after - balance_before, 10 * T2);
    }
    function testAnotherSplitTransfersToSeller() public {
        var (, base) = newAuction();

        var (, sid) = bidder1.doBid(base, 20 * T2, 80 * T1, false);

        var balance_before = t2.balanceOf(seller);
        bidder2.doBid(sid, 20 * T2, 40 * T1, false);
        var balance_after = t2.balanceOf(seller);

        assertEq(balance_after - balance_before, 10 * T2);
    }
    function testAnotherSplitTransfersFromSplitter() public {
        var (, base) = newAuction();

        var (, sid) = bidder1.doBid(base, 20 * T2, 80 * T1, false);

        var balance_before = t2.balanceOf(bidder2);
        bidder2.doBid(sid, 20 * T2, 40 * T1, false);
        var balance_after = t2.balanceOf(bidder2);

        assertEq(balance_before - balance_after, 20 * T2);
    }
    function testSplitTransfersToSeller() public {
        var (, base) = newAuction();

        var (nid, ) = bidder1.doBid(base, 20 * T2, 80 * T1, false);

        var balance_before = t2.balanceOf(seller);
        bidder2.doBid(nid, 20 * T2, 10 * T1, false);
        var balance_after = t2.balanceOf(seller);

        assertEq(balance_after - balance_before, 20 * T2);
    }
    function testBidTransfersToPrevSplitter() public {
        var (, base) = newAuction();

        var (, sid) = bidder1.doBid(base, 20 * T2, 80 * T1, false);

        var balance_before = t2.balanceOf(bidder1);
        bidder2.doBid(sid, 30 * T2, false);
        var balance_after = t2.balanceOf(bidder1);

        assertEq(balance_after - balance_before, 20 * T2);
    }
    function testSplitBaseAddresses() public {
        var (, base) = newAuction();

        var (nid, sid) = bidder1.doBid(base, 7 * T2, 60 * T1, false);

        var (auction_id1, last_bidder1, , ) = manager.getAuctionlet(nid);
        var (auction_id2, last_bidder2, , ) = manager.getAuctionlet(sid);

        assertEq(auction_id1, auction_id2);
        assertEq(last_bidder1, seller);
        assertEq(last_bidder2, bidder1);
    }
    function testSplitBaseResult() public {
        var (, base) = newAuction();

        var (nid, sid) = bidder1.doBid(base, 5 * T2, 40 * T1, false);

        uint sell_amount1;
        uint sell_amount2;

        uint buy_amount1;
        uint buy_amount2;

        uint _;
        address __;

        (_, __, buy_amount1, sell_amount1) = manager.getAuctionlet(nid);
        (_, __, buy_amount2, sell_amount2) = manager.getAuctionlet(sid);

        var expected_new_sell_amount1 = 60 * T1;
        var expected_new_sell_amount2 = 40 * T1;

        assertEq(sell_amount1, expected_new_sell_amount1);
        assertEq(sell_amount2, expected_new_sell_amount2);

        // we expect the bid on the existing auctionlet to remain at the
        // start bid scaled down proportionally as it is a base auctionlet
        var expected_new_bid1 = 6 * T2;
        var expected_new_bid2 = 5 * T2;

        assertEq(buy_amount1, expected_new_bid1);
        assertEq(buy_amount2, expected_new_bid2);
    }
    function testSplitAfterBidAddresses() public {
        var (, base) = newAuction();

        bidder1.doBid(base, 11 * T2, false);

        // make split bid that has equivalent price of 20 T2 for full lot
        var (nid, sid) = bidder2.doBid(base, 12 * T2, 60 * T1, false);

        var (auction_id1, last_bidder1, , ) = manager.getAuctionlet(nid);
        var (auction_id2, last_bidder2, , ) = manager.getAuctionlet(sid);

        assertEq(auction_id1, auction_id2);
        assertEq(last_bidder1, bidder1);
        assertEq(last_bidder2, bidder2);
    }
    function testSplitAfterBidQuantities() public {
        var (, base) = newAuction();

        bidder1.doBid(base, 11 * T2, false);

        // make split bid that has equivalent price of 20 T2 for full lot
        var (nid, sid) = bidder2.doBid(base, 12 * T2, 60 * T1, false);

        uint sell_amount1;
        uint sell_amount2;

        uint buy_amount1;
        uint buy_amount2;

        uint _;
        address __;

        (_, __, buy_amount1, sell_amount1) = manager.getAuctionlet(nid);
        (_, __, buy_amount2, sell_amount2) = manager.getAuctionlet(sid);

        // Splitting a bid produces two new bids - the 'splitting' bid
        // and a 'modified' bid.
        // The original bid has sell_amount q0 and bid amount b0.
        // The modified bid has sell_amount q1 and bid amount b1.
        // The splitting bid has sell_amount q2 and bid amount b2.
        // The splitting bid must satisfy (b2 / q2) > (b0 / q0)
        // and q2 < q0, i.e. it must be an increase in order valuation,
        // but a decrease in sell_amount.
        // The modified bid conserves *valuation*: (q1 / b1) = (q0 / b0)
        // and has reduced sell_amount: q1 = q0 - q2.
        // The unknown modified bid b1 is determined by b1 = b0 (q1 / q0),
        // i.e. the original bid scaled by the sell_amount change.

        var expected_new_sell_amount2 = 60 * T1;
        var expected_new_bid2 = 12 * T2;

        var expected_new_sell_amount1 = 100 * T1 - expected_new_sell_amount2;
        var expected_new_bid1 = (11 * T2 * expected_new_sell_amount1) / (100 * T1);

        assertEq(sell_amount1, expected_new_sell_amount1);
        assertEq(sell_amount2, expected_new_sell_amount2);

        assertEq(buy_amount1, expected_new_bid1);
        assertEq(buy_amount2, expected_new_bid2);
    }
    function testFailSplitExcessQuantity() public {
        var (, base) = newAuction();
        bidder1.doBid(base, 7 * T2, 101 * T1, false);
    }
    function testPassSplitLowerValue() public {
        // The splitting bid must satisfy (b2 / q2) > (b0 / q0)
        // and q2 < q0, i.e. it must be an increase in order valuation,
        // but a decrease in sell_amount.
        var (, base) = newAuction();
        bidder1.doBid(base, 6 * T2, 50 * T1, false);
    }
    function testFailSplitLowerValue() public {
        // The splitting bid must satisfy (b2 / q2) > (b0 / q0)
        // and q2 < q0, i.e. it must be an increase in order valuation,
        // but a decrease in sell_amount.
        var (, base) = newAuction();
        bidder1.doBid(base, 11 * T2, false);

        bidder2.doBid(base, 5 * T2, 50 * T1, false);
    }
    function testFailSplitUnderMinBid() public {
        // Splitting bids have to be over the scaled minimum bid
        var (, base) = newAuction();
        bidder1.doBid(base, 4 * T2, 50 * T1, false);
    }
    function testFailSplitUnderMinIncrease() public {
        // Splitting bids have to increase more than the scaled minimum
        // increase
        var (, base) = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 10, 1 years);
        bidder1.doBid(base, 10 * T2, false);

        bidder2.doBid(base, 6 * T2, 50 * T1, false);
    }
    function testFailSplitExpired() public {
        var (, base) = newAuction();
        bidder1.doBid(base, 11 * T2, false);

        // force expiry
        manager.addTime(2 years);

        bidder2.doBid(base, 10 * T2, 50 * T1, false);
    }
    function testSplitReturnsToPrevBidder() public {
        var (, base) = newAuction();

        var bidder1_t2_balance_before = t2.balanceOf(bidder1);
        bidder1.doBid(base, 20 * T2, false);
        bidder2.doBid(base, 20 * T2, 50 * T1, false);
        var bidder1_t2_balance_after = t2.balanceOf(bidder1);

        var bidder_balance_diff = bidder1_t2_balance_before - bidder1_t2_balance_after;
        assertEq(bidder_balance_diff, 10 * T2);
    }
    function testSplitBaseTransfersToBenefactor() public {

        var (, base) = newAuction();

        var balance_before = t2.balanceOf(seller);
        bidder2.doBid(base, 20 * T2, 25 * T1, false);
        var balance_after = t2.balanceOf(seller);

        assertEq(balance_after - balance_before, 20 * T2);
    }
    function testSplitTransfersBenefactor() public {
        var (, base) = newAuction();

        var balance_before = t2.balanceOf(seller);
        bidder1.doBid(base, 40 * T2, false);
        bidder2.doBid(base, 20 * T2, 25 * T1, false);

        var balance_after = t2.balanceOf(seller);

        assertEq(balance_after - balance_before, 50 * T2);
    }
    function testFailSplitAfterSplit() public {
        // splitting deletes the old auctionlet_id
        // splitting on this id should error
        var (, base) = newAuction();
        bidder2.doBid(base, 12 * T2, 60 * T1, false);
        bidder1.doBid(base, 20 * T2, 60 * T1, false);
    }
    function testBaseDoesNotExpire() public {
        var (, base) = newAuction();

        var (nid, ) = bidder1.doBid(base, 7 * T2, 60 * T1, false);

        // push past the base auction ttl
        manager.addTime(2 years);

        // this should succeed as there are no real bidders
        bidder1.doBid(nid, 11 * T2, false);
    }
    function testFailSplitExpires() public {
        var (, base) = newAuction();

        var (, sid) = bidder1.doBid(base, 7 * T2, 60 * T1, false);

        // push past the base auction ttl
        manager.addTime(2 years);

        // this should succeed as there are no real bidders
        bidder1.doBid(sid, 11 * T2, false);
    }
    function testIndependentExpirations() public {
        var (, base) = newAuction();

        var (nid, sid) = bidder1.doBid(base, 7 * T2, 60 * T1, false);

        manager.addTime(200 days);
        bidder1.doBid(nid, 10 * T2, false);
        manager.addTime(200 days);

        assert(manager.isExpired(sid));
        assert(!manager.isExpired(nid));
    }
}
