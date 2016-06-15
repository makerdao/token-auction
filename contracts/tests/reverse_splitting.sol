import 'tests/base.sol';

import 'splitting_auction.sol';

contract ReverseSplittingTest is AuctionTest {
    function newReverseAuction() returns (uint, uint) {
        return manager.newReverseAuction( seller    // beneficiary
                                        , t1        // selling
                                        , t2        // buying
                                        , 100 * T1  // sell_amount
                                        , 5 * T2    // buy_amount
                                        , 2 * T1    // min_decrease
                                        , 1 years   // duration
                                        );
    }
    function testNewReverseAuction() {
        var (id, base) = newReverseAuction();

        assertEq(manager.getCollectMax(id), 0);
        assertEq(manager.isReversed(id), true);

        var (auction_id, last_bidder,
             buy_amount, sell_amount) = manager.getAuctionlet(base);

        assertEq(auction_id, 1);
        assertEq(last_bidder, seller);
        assertEq(buy_amount, 5 * T2);
        assertEq(sell_amount, 100 * T1);
    }
    function testSplitBase() {
        var (id, base) = newReverseAuction();

        var (auction_id0, last_bidder0,
             last_bid0, quantity0) = manager.getAuctionlet(base);

        var (nid, sid) = bidder1.doBid(base, 40 * T1, 4 * T2);

        var (auction_id1, last_bidder1,
             last_bid1, quantity1) = manager.getAuctionlet(nid);

        var expected_new_buy_amount = 1 * T2;
        var expected_new_sell_amount = 20 * T1;

        assertEq(auction_id0, auction_id1);
        assertEq(last_bidder0, seller);
        assertEq(last_bidder1, seller);

        assertEq(last_bid0, 5 * T2);
        assertEq(quantity0, 100 * T1);

        assertEq(last_bid1, expected_new_buy_amount);
        assertEq(quantity1, expected_new_sell_amount);
    }
    function testSplitBaseTransfersFromBidder() {
        var (id, base) = newReverseAuction();

        var bidder1_t2_balance_before = t2.balanceOf(bidder1);
        bidder1.doBid(base, 40 * T1, 4 * T2);
        var bidder1_t2_balance_after = t2.balanceOf(bidder1);

        var balance_diff = bidder1_t2_balance_before - bidder1_t2_balance_after;
        assertEq(balance_diff, 4 * T2);
    }
    function testSplitBaseAddresses() {
        var (id, base) = newReverseAuction();

        var (nid, sid) = bidder1.doBid(base, 40 * T1, 4 * T2);

        var (auction_id1, last_bidder1,
             buy_amount1, sell_amount1) = manager.getAuctionlet(nid);
        var (auction_id2, last_bidder2,
             buy_amount2, sell_amount2) = manager.getAuctionlet(sid);

        assertEq(auction_id1, auction_id2);
        assertEq(last_bidder1, seller);
        assertEq(last_bidder2, bidder1);
    }
    function testSplitBaseResult() {
        var (id, base) = newReverseAuction();

        var (nid, sid) = bidder1.doBid(base, 40 * T1, 4 * T2);

        uint sell_amount1;
        uint sell_amount2;

        uint buy_amount1;
        uint buy_amount2;

        uint _;
        address __;

        (_, __, buy_amount1, sell_amount1) = manager.getAuctionlet(nid);
        (_, __, buy_amount2, sell_amount2) = manager.getAuctionlet(sid);

        var expected_new_sell_amount1 = 20 * T1;
        var expected_new_sell_amount2 = 40 * T1;

        assertEq(sell_amount1, expected_new_sell_amount1);
        assertEq(sell_amount2, expected_new_sell_amount2);

        // we expect the bid on the existing auctionlet to remain at the
        // start bid scaled down proportionally as it is a base auctionlet
        var expected_new_buy_amount1 = 1 * T2;
        var expected_new_buy_amount2 = 4 * T2;

        assertEq(buy_amount1, expected_new_buy_amount1);
        assertEq(buy_amount2, expected_new_buy_amount2);
    }
    function testSplitAfterBidAddresses() {
        var (id, base) = newReverseAuction();
        bidder1.doBid(base, 90 * T1);
        var (nid, sid) = bidder2.doBid(base, 40 * T1, 4 * T2);

        var (auction_id1, last_bidder1,
             buy_amount1, sell_amount1) = manager.getAuctionlet(nid);
        var (auction_id2, last_bidder2,
             buy_amount2, sell_amount2) = manager.getAuctionlet(sid);

        assertEq(auction_id1, auction_id2);
        assertEq(last_bidder1, bidder1);
        assertEq(last_bidder2, bidder2);
    }
    function testSplitAfterBidQuantities() {
        var (id, base) = newReverseAuction();
        bidder1.doBid(base, 90 * T1);
        var (nid, sid) = bidder2.doBid(base, 40 * T1, 4 * T2);

        uint sell_amount1;
        uint sell_amount2;

        uint buy_amount1;
        uint buy_amount2;

        uint _;
        address __;

        (_, __, buy_amount1, sell_amount1) = manager.getAuctionlet(nid);
        (_, __, buy_amount2, sell_amount2) = manager.getAuctionlet(sid);

        var expected_new_buy_amount2 = 4 * T2;
        var expected_new_sell_amount2 = 40 * T1;

        var expected_new_buy_amount1 = 5 * T2 - expected_new_buy_amount2;
        var expected_new_sell_amount1 = (90 * T1 * expected_new_buy_amount1) / (5 * T2);

        assertEq(sell_amount1, expected_new_sell_amount1);
        assertEq(sell_amount2, expected_new_sell_amount2);

        assertEq(buy_amount1, expected_new_buy_amount1);
        assertEq(buy_amount2, expected_new_buy_amount2);
    }
    function testFailSplitExcessQuantity() {
        var (id, base) = newReverseAuction();
        bidder1.doBid(base, 90 * T2, 6 * T1);
    }
    function testPassSplitLowerValue() {
        var (id, base) = newReverseAuction();
        bidder1.doBid(base, 50 * T1, 3 * T2);
    }
    function testFailSplitLowerValue() {
        var (id, base) = newReverseAuction();
        bidder1.doBid(base, 80 * T1);
        bidder2.doBid(base, 40 * T1, 2 * T2);
    }
    function testFailSplitUnderMinBid() {
        var (id, base) = newReverseAuction();
        bidder2.doBid(base, 50 * T1, 2 * T2);
    }
    function testFailSplitUnderMinDecrease() {
        var (id, base) = newReverseAuction();
        bidder1.doBid(base, 90 * T1);
        bidder2.doBid(base, 89 * T1, 3 * T2);
    }
    function testFailSplitExpired() {
        var (id, base) = newReverseAuction();
        bidder1.doBid(base, 90 * T1);

        // force expiry
        manager.setTime(manager.getTime() + 2 years);

        bidder2.doBid(base, 40 * T1, 4 * T2);
    }
    function testSplitReturnsToPrevBidder() {
        var (id, base) = newReverseAuction();

        var bidder1_t2_balance_before = t2.balanceOf(bidder1);
        bidder1.doBid(base, 90 * T1);
        bidder2.doBid(base, 50 * T1, 3 * T2);
        var bidder1_t2_balance_after = t2.balanceOf(bidder1);

        var bidder_balance_diff = bidder1_t2_balance_before - bidder1_t2_balance_after;
        assertEq(bidder_balance_diff, 2 * T2);
    }
    function testTransferToBenefactorAfterSplit() {
        var (id, base) = newReverseAuction();

        var balance_before = t1.balanceOf(seller);
        bidder1.doBid(base, 80 * T1);
        bidder2.doBid(base, 40 * T1, 4 * T2);
        var balance_after = t1.balanceOf(seller);

        //@log seller t1 balance change
        // 20 + 80 * (4 / 5) - 40 = 44
        assertEq(balance_after - balance_before, 44 * T1);
    }
    function testCreatorReclaimAfterBaseSplit() {
        var (id, base) = newReverseAuction();

        bidder1.doBid(base, 50 * T1, 3 * T2);

        // force expiry
        manager.setTime(manager.getTime() + 2 years);

        var balance_before = t1.balanceOf(this);
        manager.reclaim(id);
        var balance_after = t1.balanceOf(this);

        // check that the unsold sell tokens are sent back
        // to the creator.
        // 100 * (5 - 3) / 5 = 40
        assertEq(balance_after - balance_before, 40 * T1);
    }
    function testCreatorReclaimAfterSplitBaseSplit() {
        var (id, base) = newReverseAuction();

        var (nid, sid) = bidder1.doBid(base, 50 * T1, 3 * T2);
        bidder2.doBid(sid, 20 * T1, 2 * T2);

        // force expiry
        manager.setTime(manager.getTime() + 2 years);

        var balance_before = t1.balanceOf(this);
        manager.reclaim(id);
        var balance_after = t1.balanceOf(this);

        // There should still be the same number of tokens available for
        // reclaim as the second split is a sub-split of the first.
        // 100 * (5 - 3) / 5 = 40
        assertEq(balance_after - balance_before, 40 * T1);
    }
}
