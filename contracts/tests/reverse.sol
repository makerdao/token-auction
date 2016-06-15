import 'tests/base.sol';

import 'auction_manager.sol';

contract ReverseTest is AuctionTest {
    function newReverseAuction() returns (uint, uint) {
        return manager.newReverseAuction( seller    // beneficiary
                                        , t1        // selling
                                        , t2        // buying
                                        , 100 * T1  // max_sell_amount
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
    function testNewReverseAuctionTransfersFromCreator() {
        var balance_before = t1.balanceOf(this);
        var (id, base) = newReverseAuction();
        var balance_after = t1.balanceOf(this);

        assertEq(balance_before - balance_after, 100 * T1);
    }
    function testNewReverseAuctionTransfersToManager() {
        var balance_before = t1.balanceOf(manager);
        var (id, base) = newReverseAuction();
        var balance_after = t1.balanceOf(manager);

        assertEq(balance_after - balance_before, 100 * T1);
    }
    function testFirstBidTransfersFromBidder() {
        var (id, base) = newReverseAuction();

        var bidder_t2_balance_before = t2.balanceOf(bidder1);
        bidder1.doBid(base, 90 * T1);
        var bidder_t2_balance_after = t2.balanceOf(bidder1);

        // bidder should have reduced funds
        assertEq(bidder_t2_balance_before - bidder_t2_balance_after, 5 * T2);
    }
    function testFirstBidTransfersBuyTokenToBenefactor() {
        var (id, base) = newReverseAuction();

        var balance_before = t2.balanceOf(seller);
        bidder1.doBid(base, 90 * T1);
        var balance_after = t2.balanceOf(seller);

        // beneficiary should have received all the available buy
        // token, as a bidder has committed to the auction
        assertEq(balance_after - balance_before, 5 * T2);
    }
    function testFirstBidTransfersExcessSellTokenToBenefactor() {
        var (base, id) = newReverseAuction();

        var balance_before = t1.balanceOf(seller);
        bidder1.doBid(1, 85 * T1);
        var balance_after = t1.balanceOf(seller);

        // beneficiary should have received the excess sell token
        assertEq(balance_after - balance_before, 15 * T1);
    }
    function testFailFirstBidOverStartBid() {
        var (id, base) = newReverseAuction();
        bidder1.doBid(base, 105 * T1);
    }
    function testFailNextBidUnderMinimum() {
        var (id, base) = newReverseAuction();
        bidder1.doBid(base, 90 * T1);
        bidder1.doBid(base, 89 * T1);
    }
    function testFailNextBidOverLast() {
        var (id, base) = newReverseAuction();
        bidder1.doBid(base, 90 * T1);
        bidder1.doBid(base, 91 * T1);
    }
    function testNextBidRefundsPreviousBidder() {
        var (id, base) = newReverseAuction();

        var bidder_t2_balance_before = t2.balanceOf(bidder1);
        bidder1.doBid(base, 90 * T1);
        bidder2.doBid(base, 85 * T1);
        var bidder_t2_balance_after = t2.balanceOf(bidder1);

        // bidder should have reduced funds
        assertEq(bidder_t2_balance_before - bidder_t2_balance_after, 0);
    }
    function testNextBidTransfersNoExtraBuyToken() {
        var (id, base) = newReverseAuction();

        bidder1.doBid(base, 90 * T1);

        var balance_before = t2.balanceOf(seller);
        bidder2.doBid(base, 85 * T1);
        var balance_after = t2.balanceOf(seller);

        assertEq(balance_after, balance_before);
    }
    function testNextBidTransfersExcessSellToken() {
        var (id, base) = newReverseAuction();

        bidder1.doBid(base, 90 * T1);

        var balance_before = t1.balanceOf(seller);
        bidder2.doBid(base, 85 * T1);
        var balance_after = t1.balanceOf(seller);

        assertEq(balance_after - balance_before, 5 * T1);
    }
    function testClaimBidder() {
        var (base, id) = newReverseAuction();
        bidder1.doBid(1, 85 * T1);

        // force expiry
        manager.addTime(2 years);

        var t1_balance_before = t1.balanceOf(bidder1);
        bidder1.doClaim(1);
        var t1_balance_after = t1.balanceOf(bidder1);
        var t1_balance_diff = t1_balance_after - t1_balance_before;

        assertEq(t1_balance_diff, 85 * T1);
    }
}
