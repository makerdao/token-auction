pragma solidity ^0.4.15;

import './base.t.sol';

contract ReverseTest is AuctionTest {
    function newReverseAuction() public returns (uint, uint) {
        return manager.newReverseAuction( seller    // beneficiary
                                        , t1        // selling
                                        , t2        // buying
                                        , 100 * T1  // max_sell_amount
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
    function testNewReverseAuctionTransfersFromCreator() public {
        var balance_before = t1.balanceOf(this);
        newReverseAuction();
        var balance_after = t1.balanceOf(this);

        assertEq(balance_before - balance_after, 100 * T1);
    }
    function testNewReverseAuctionTransfersToManager() public {
        var balance_before = t1.balanceOf(manager);
        newReverseAuction();
        var balance_after = t1.balanceOf(manager);

        assertEq(balance_after - balance_before, 100 * T1);
    }
    function testFirstBidTransfersFromBidder() public {
        var (, base) = newReverseAuction();

        var bidder_t2_balance_before = t2.balanceOf(bidder1);
        bidder1.doBid(base, 90 * T1, true);
        var bidder_t2_balance_after = t2.balanceOf(bidder1);

        // bidder should have reduced funds
        assertEq(bidder_t2_balance_before - bidder_t2_balance_after, 5 * T2);
    }
    function testFirstBidTransfersBuyTokenToBenefactor() public {
        var (, base) = newReverseAuction();

        var balance_before = t2.balanceOf(seller);
        bidder1.doBid(base, 90 * T1, true);
        var balance_after = t2.balanceOf(seller);

        // beneficiary should have received all the available buy
        // token, as a bidder has committed to the auction
        assertEq(balance_after - balance_before, 5 * T2);
    }
    function testFirstBidTransfersExcessSellTokenToBenefactor() public {
        newReverseAuction();

        var balance_before = t1.balanceOf(seller);
        bidder1.doBid(1, 85 * T1, true);
        var balance_after = t1.balanceOf(seller);

        // beneficiary should have received the excess sell token
        assertEq(balance_after - balance_before, 15 * T1);
    }
    function testFailFirstBidOverStartBid() public {
        var (, base) = newReverseAuction();
        bidder1.doBid(base, 105 * T1, true);
    }
    function testFailNextBidUnderMinimum() public {
        var (, base) = newReverseAuction();
        bidder1.doBid(base, 90 * T1, true);
        bidder1.doBid(base, 89 * T1, true);
    }
    function testFailNextBidOverLast() public {
        var (, base) = newReverseAuction();
        bidder1.doBid(base, 90 * T1, true);
        bidder1.doBid(base, 91 * T1, true);
    }
    function testNextBidRefundsPreviousBidder() public {
        var (, base) = newReverseAuction();

        var bidder_t2_balance_before = t2.balanceOf(bidder1);
        bidder1.doBid(base, 90 * T1, true);
        bidder2.doBid(base, 85 * T1, true);
        var bidder_t2_balance_after = t2.balanceOf(bidder1);

        // bidder should have reduced funds
        assertEq(bidder_t2_balance_before - bidder_t2_balance_after, 0);
    }
    function testNextBidTransfersNoExtraBuyToken() public {
        var (, base) = newReverseAuction();

        bidder1.doBid(base, 90 * T1, true);

        var balance_before = t2.balanceOf(seller);
        bidder2.doBid(base, 85 * T1, true);
        var balance_after = t2.balanceOf(seller);

        assertEq(balance_after, balance_before);
    }
    function testNextBidTransfersExcessSellToken() public {
        var (, base) = newReverseAuction();

        bidder1.doBid(base, 90 * T1, true);

        var balance_before = t1.balanceOf(seller);
        bidder2.doBid(base, 85 * T1, true);
        var balance_after = t1.balanceOf(seller);

        assertEq(balance_after - balance_before, 5 * T1);
    }
    function testClaimBidder() public {
        newReverseAuction();
        bidder1.doBid(1, 85 * T1, true);

        // force expiry
        manager.addTime(2 years);

        var t1_balance_before = t1.balanceOf(bidder1);
        bidder1.doClaim(1);
        var t1_balance_after = t1.balanceOf(bidder1);
        var t1_balance_diff = t1_balance_after - t1_balance_before;

        assertEq(t1_balance_diff, 85 * T1);
    }
}

contract MinBidDecreaseTest is AuctionTest {
    function newReverseAuction() public returns (uint, uint) {
        return manager.newReverseAuction( seller    // beneficiary
                                        , t1        // selling
                                        , t2        // buying
                                        , 100 * T1  // max_sell_amount
                                        , 5 * T2    // buy_amount
                                        , 20        // min_decrease (%)
                                        , 1 years   // ttl
                                        );
    }
    function testFailFirstBidEqualStartBid() public {
        var (, base) = newReverseAuction();
        bidder1.doBid(base, 100 * T1, true);
    }
    function testFailSubsequentBidEqualLastBid() public {
        var (, base) = newReverseAuction();
        bidder1.doBid(base, 75 * T1, true);
        bidder2.doBid(base, 75 * T1, true);
    }
    function testFailFirstBidHigherThanMinDecrease() public {
        var (, base) = newReverseAuction();
        bidder1.doBid(base, 90 * T1, true);
    }
    function testFailSubsequentBidHigherThanMinDecrease() public {
        var (, base) = newReverseAuction();
        bidder1.doBid(base, 75 * T1, true);
        bidder2.doBid(base, 70 * T1, true);
    }
}

contract ReverseRefundTest is AuctionTest {
    function newTwoWayAuction() public returns (uint, uint) {
        return manager.newReverseAuction( seller        // beneficiary
                                        , beneficiary1  // refund
                                        , t1            // selling
                                        , t2            // buying
                                        , 100 * T1      // max_sell_amount
                                        , 5 * T2        // buy_amount
                                        , 20            // min_decrease (%)
                                        , 1 years       // ttl
                                        );
    }
    function testNewReverseAuction() public {
        var (id, ) = newTwoWayAuction();
        assertEq(manager.getRefundAddress(id), beneficiary1);
    }
}
