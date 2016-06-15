import 'tests/base.sol';

import 'splitting_auction.sol';

contract ForwardSplittingTest is AuctionTest
                               , EventfulAuction
                               , EventfulManager
                               , EventfulSplitter
{
    function newAuction() returns (uint, uint) {
        return manager.newAuction( seller    // beneficiary
                                 , t1        // selling
                                 , t2        // buying
                                 , 100 * T1  // sell_amount
                                 , 10 * T2   // start_bid
                                 , 1 * T2    // min_increase
                                 , 1 years   // duration
                                 );
    }
    function testSplitEvent() {
        var (id, base) = newAuction();

        var (nid1, sid1) = bidder1.doBid(base, 5 * T2, 40 * T1);
        var (nid2, sid2) = bidder2.doBid(nid1, 6 * T2, 40 * T1);
        var (nid3, sid3) = bidder1.doBid(sid1, 6 * T2, 30 * T1);

        expectEventsExact(manager);
        NewAuction(id, base);
        Split(base, nid1, sid1);
        Split(nid1, nid2, sid2);
        Split(sid1, nid3, sid3);
    }
    function testSplitBase() {
        var (id, base) = newAuction();

        var (auction_id0, last_bidder0,
             buy_amount0, sell_amount0) = manager.getAuctionlet(base);

        var (nid, sid) = bidder1.doBid(base, 5 * T2, 40 * T1);

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
    function testSplitTransfersFromBidder() {
        var (id, base) = newAuction();

        var balance_before = t2.balanceOf(bidder1);
        bidder1.doBid(base, 7 * T2, 60 * T1);
        var balance_after = t2.balanceOf(bidder1);

        assertEq(balance_before - balance_after, 7 * T2);
    }
    function testSplitBaseTransfersToSeller() {
        var (id, base) = newAuction();

        var balance_before = t2.balanceOf(seller);
        bidder1.doBid(base, 7 * T2, 60 * T1);
        var balance_after = t2.balanceOf(seller);

        assertEq(balance_after - balance_before, 7 * T2);
    }
    function testSplitTransfersToPrevBidder() {
        var (id, base) = newAuction();

        bidder1.doBid(base, 20 * T2);

        var balance_before = t2.balanceOf(bidder1);
        bidder2.doBid(base, 20 * T2, 50 * T1);
        var balance_after = t2.balanceOf(bidder1);

        assertEq(balance_after - balance_before, 10 * T2);
    }
    function testAnotherSplitTransfersToPrevSplitter() {
        var (id, base) = newAuction();

        var (nid, sid) = bidder1.doBid(base, 20 * T2, 80 * T1);

        var balance_before = t2.balanceOf(bidder1);
        bidder2.doBid(sid, 20 * T2, 40 * T1);
        var balance_after = t2.balanceOf(bidder1);

        assertEq(balance_after - balance_before, 10 * T2);
    }
    function testAnotherSplitTransfersToSeller() {
        var (id, base) = newAuction();

        var (nid, sid) = bidder1.doBid(base, 20 * T2, 80 * T1);

        var balance_before = t2.balanceOf(seller);
        bidder2.doBid(sid, 20 * T2, 40 * T1);
        var balance_after = t2.balanceOf(seller);

        assertEq(balance_after - balance_before, 10 * T2);
    }
    function testAnotherSplitTransfersFromSplitter() {
        var (id, base) = newAuction();

        var (nid, sid) = bidder1.doBid(base, 20 * T2, 80 * T1);

        var balance_before = t2.balanceOf(bidder2);
        bidder2.doBid(sid, 20 * T2, 40 * T1);
        var balance_after = t2.balanceOf(bidder2);

        assertEq(balance_before - balance_after, 20 * T2);
    }
    function testSplitTransfersToSeller() {
        var (id, base) = newAuction();

        var (nid, sid) = bidder1.doBid(base, 20 * T2, 80 * T1);

        var balance_before = t2.balanceOf(seller);
        bidder2.doBid(nid, 20 * T2, 10 * T1);
        var balance_after = t2.balanceOf(seller);

        assertEq(balance_after - balance_before, 20 * T2);
    }
    function testBidTransfersToPrevSplitter() {
        var (id, base) = newAuction();

        var (nid, sid) = bidder1.doBid(base, 20 * T2, 80 * T1);

        var balance_before = t2.balanceOf(bidder1);
        bidder2.doBid(sid, 30 * T2);
        var balance_after = t2.balanceOf(bidder1);

        assertEq(balance_after - balance_before, 20 * T2);
    }
    function testSplitBaseAddresses() {
        var (id, base) = newAuction();

        var (nid, sid) = bidder1.doBid(base, 7 * T2, 60 * T1);

        var (auction_id1, last_bidder1,
             buy_amount1, sell_amount1) = manager.getAuctionlet(nid);
        var (auction_id2, last_bidder2,
             buy_amount2, sell_amount2) = manager.getAuctionlet(sid);

        assertEq(auction_id1, auction_id2);
        assertEq(last_bidder1, seller);
        assertEq(last_bidder2, bidder1);
    }
    function testSplitBaseResult() {
        var (id, base) = newAuction();

        var (nid, sid) = bidder1.doBid(base, 5 * T2, 40 * T1);

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
    function testSplitAfterBidAddresses() {
        var (id, base) = newAuction();

        bidder1.doBid(base, 11 * T2);

        // make split bid that has equivalent price of 20 T2 for full lot
        var (nid, sid) = bidder2.doBid(base, 12 * T2, 60 * T1);

        var (auction_id1, last_bidder1,
             buy_amount1, sell_amount1) = manager.getAuctionlet(nid);
        var (auction_id2, last_bidder2,
             buy_amount2, sell_amount2) = manager.getAuctionlet(sid);

        assertEq(auction_id1, auction_id2);
        assertEq(last_bidder1, bidder1);
        assertEq(last_bidder2, bidder2);
    }
    function testSplitAfterBidQuantities() {
        var (id, base) = newAuction();

        bidder1.doBid(base, 11 * T2);

        // make split bid that has equivalent price of 20 T2 for full lot
        var (nid, sid) = bidder2.doBid(base, 12 * T2, 60 * T1);

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
    function testFailSplitExcessQuantity() {
        var (id, base) = newAuction();
        bidder1.doBid(base, 7 * T2, 101 * T1);
    }
    function testPassSplitLowerValue() {
        // The splitting bid must satisfy (b2 / q2) > (b0 / q0)
        // and q2 < q0, i.e. it must be an increase in order valuation,
        // but a decrease in sell_amount.
        var (id, base) = newAuction();
        bidder1.doBid(base, 6 * T2, 50 * T1);
    }
    function testFailSplitLowerValue() {
        // The splitting bid must satisfy (b2 / q2) > (b0 / q0)
        // and q2 < q0, i.e. it must be an increase in order valuation,
        // but a decrease in sell_amount.
        var (id, base) = newAuction();
        bidder1.doBid(base, 11 * T2);

        bidder2.doBid(base, 5 * T2, 50 * T1);
    }
    function testFailSplitUnderMinBid() {
        // Splitting bids have to be over the scaled minimum bid
        var (id, base) = newAuction();
        bidder1.doBid(base, 4 * T2, 50 * T1);
    }
    function testFailSplitUnderMinIncrease() {
        // Splitting bids have to increase more than the scaled minimum
        // increase
        var (id, base) = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 10 * T2, 1 years);
        bidder1.doBid(base, 10 * T2);

        bidder2.doBid(base, 6 * T2, 50 * T1);
    }
    function testFailSplitExpired() {
        var (id, base) = newAuction();
        bidder1.doBid(base, 11 * T2);

        // force expiry
        manager.addTime(2 years);

        bidder2.doBid(base, 10 * T2, 50 * T1);
    }
    function testSplitReturnsToPrevBidder() {
        var (id, base) = newAuction();

        var bidder1_t2_balance_before = t2.balanceOf(bidder1);
        bidder1.doBid(base, 20 * T2);
        bidder2.doBid(base, 20 * T2, 50 * T1);
        var bidder1_t2_balance_after = t2.balanceOf(bidder1);

        var bidder_balance_diff = bidder1_t2_balance_before - bidder1_t2_balance_after;
        assertEq(bidder_balance_diff, 10 * T2);
    }
    function testSplitBaseTransfersToBenefactor() {

        var (id, base) = newAuction();

        var balance_before = t2.balanceOf(seller);
        bidder2.doBid(base, 20 * T2, 25 * T1);
        var balance_after = t2.balanceOf(seller);

        assertEq(balance_after - balance_before, 20 * T2);
    }
    function testSplitTransfersBenefactor() {
        var (id, base) = newAuction();

        var balance_before = t2.balanceOf(seller);
        bidder1.doBid(base, 40 * T2);
        bidder2.doBid(base, 20 * T2, 25 * T1);

        var balance_after = t2.balanceOf(seller);

        assertEq(balance_after - balance_before, 50 * T2);
    }
    function testFailBidAfterSplit() {
        // splitting deletes the old auctionlet_id
        // bidding on this id should error
        var (id, base) = newAuction();
        var (nid, sid) = bidder2.doBid(base, 12 * T2, 60 * T1);
        bidder1.doBid(base, 11 * T2);
    }
    function testFailSplitAfterSplit() {
        // splitting deletes the old auctionlet_id
        // splitting on this id should error
        var (id, base) = newAuction();
        var (nid, sid) = bidder2.doBid(base, 12 * T2, 60 * T1);
        bidder1.doBid(base, 20 * T2, 60 * T1);
    }
    function testBaseDoesNotExpire() {
        var (id, base) = newAuction();

        var (nid, sid) = bidder1.doBid(base, 7 * T2, 60 * T1);

        // push past the base auction duration
        manager.addTime(2 years);

        // this should succeed as there are no real bidders
        bidder1.doBid(nid, 11 * T2);
    }
    function testFailSplitExpires() {
        var (id, base) = newAuction();

        var (nid, sid) = bidder1.doBid(base, 7 * T2, 60 * T1);

        // push past the base auction duration
        manager.addTime(2 years);

        // this should succeed as there are no real bidders
        bidder1.doBid(sid, 11 * T2);
    }
    function testIndependentExpirations() {
        var (id, base) = newAuction();

        var (nid, sid) = bidder1.doBid(base, 7 * T2, 60 * T1);

        manager.addTime(200 days);
        bidder1.doBid(nid, 10 * T2);
        manager.addTime(200 days);

        assertTrue(manager.isExpired(sid));
        assertFalse(manager.isExpired(nid));
    }
}
