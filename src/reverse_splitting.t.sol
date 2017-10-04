pragma solidity ^0.4.15;

import './base.t.sol';

contract ReverseSplittingTest is AuctionTest {
    function newReverseAuction() public returns (uint, uint) {
        return manager.newReverseAuction( seller    // beneficiary
                                        , t1        // selling
                                        , t2        // buying
                                        , 100 * T1  // sell_amount
                                        , 5 * T2    // buy_amount
                                        , 2         // min_decrease (%)
                                        , 1 years   // ttl
                                        );
    }
    function testNewReverseAuction() public {
        var (id, base) = newReverseAuction();

        assertEq(manager.getCollectMax(id), 0);
        assert(manager.isReversed(id));

        var (auction_id, last_bidder,
             buy_amount, sell_amount) = manager.getAuctionlet(base);

        assertEq(auction_id, 1);
        assertEq(last_bidder, seller);
        assertEq(buy_amount, 5 * T2);
        assertEq(sell_amount, 100 * T1);
    }
    function testSplitBase() public {
        var (, base) = newReverseAuction();

        var (auction_id0, last_bidder0,
             last_bid0, quantity0) = manager.getAuctionlet(base);

        var (nid,) = bidder1.doBid(base, 40 * T1, 4 * T2, true);

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
    function testSplitBaseTransfersFromBidder() public {
        var (, base) = newReverseAuction();

        var bidder1_t2_balance_before = t2.balanceOf(bidder1);
        bidder1.doBid(base, 40 * T1, 4 * T2, true);
        var bidder1_t2_balance_after = t2.balanceOf(bidder1);

        var balance_diff = bidder1_t2_balance_before - bidder1_t2_balance_after;
        assertEq(balance_diff, 4 * T2);
    }
    function testSplitBaseAddresses() public {
        var (, base) = newReverseAuction();

        var (nid, sid) = bidder1.doBid(base, 40 * T1, 4 * T2, true);

        var (auction_id1, last_bidder1,
             ,) = manager.getAuctionlet(nid);
        var (auction_id2, last_bidder2,
             ,) = manager.getAuctionlet(sid);

        assertEq(auction_id1, auction_id2);
        assertEq(last_bidder1, seller);
        assertEq(last_bidder2, bidder1);
    }
    function testSplitBaseResult() public {
        var (, base) = newReverseAuction();

        var (nid, sid) = bidder1.doBid(base, 40 * T1, 4 * T2, true);

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
    function testSplitAfterBidAddresses() public {
        var (, base) = newReverseAuction();
        bidder1.doBid(base, 90 * T1, true);
        var (nid, sid) = bidder2.doBid(base, 40 * T1, 4 * T2, true);

        var (auction_id1, last_bidder1, , ) = manager.getAuctionlet(nid);
        var (auction_id2, last_bidder2, , ) = manager.getAuctionlet(sid);

        assertEq(auction_id1, auction_id2);
        assertEq(last_bidder1, bidder1);
        assertEq(last_bidder2, bidder2);
    }
    function testSplitAfterBidQuantities() public {
        var (, base) = newReverseAuction();
        bidder1.doBid(base, 90 * T1, true);
        var (nid, sid) = bidder2.doBid(base, 40 * T1, 4 * T2, true);

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
    function testFailSplitExcessQuantity() public {
        var (, base) = newReverseAuction();
        bidder1.doBid(base, 90 * T2, 6 * T1, true);
    }
    function testPassSplitLowerValue() public {
        var (, base) = newReverseAuction();
        bidder1.doBid(base, 50 * T1, 3 * T2, true);
    }
    function testFailSplitLowerValue() public {
        var (, base) = newReverseAuction();
        bidder1.doBid(base, 80 * T1, true);
        bidder2.doBid(base, 40 * T1, 2 * T2, true);
    }
    function testFailSplitUnderMinBid() public {
        var (, base) = newReverseAuction();
        bidder2.doBid(base, 50 * T1, 2 * T2, true);
    }
    function testFailSplitUnderMinDecrease() public {
        var (, base) = newReverseAuction();
        bidder1.doBid(base, 90 * T1, true);
        bidder2.doBid(base, 89 * T1, 3 * T2, true);
    }
    function testFailSplitExpired() public {
        var (, base) = newReverseAuction();
        bidder1.doBid(base, 90 * T1, true);

        // force expiry
        manager.addTime(2 years);

        bidder2.doBid(base, 40 * T1, 4 * T2, true);
    }
    function testSplitReturnsToPrevBidder() public {
        var (, base) = newReverseAuction();

        var bidder1_t2_balance_before = t2.balanceOf(bidder1);
        bidder1.doBid(base, 90 * T1, true);
        bidder2.doBid(base, 50 * T1, 3 * T2, true);
        var bidder1_t2_balance_after = t2.balanceOf(bidder1);

        var bidder_balance_diff = bidder1_t2_balance_before - bidder1_t2_balance_after;
        assertEq(bidder_balance_diff, 2 * T2);
    }
    function testTransferToBenefactorAfterSplit() public {
        var (, base) = newReverseAuction();

        var balance_before = t1.balanceOf(seller);
        bidder1.doBid(base, 80 * T1, true);
        bidder2.doBid(base, 40 * T1, 4 * T2, true);
        var balance_after = t1.balanceOf(seller);

        //@log seller t1 balance change
        // 20 + 80 * (4 / 5) - 40 = 44
        assertEq(balance_after - balance_before, 44 * T1);
    }
}
