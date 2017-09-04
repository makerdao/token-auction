pragma solidity ^0.4.0;

import './base.t.sol';

contract SetUpTest is AuctionTest {
    function testSetUp() {
        assertEq(t2.balanceOf(bidder1), 1000 * T2);
        assertEq(t2.allowance(bidder1, manager), 1000 * T2);
    }
}

contract NewAuctionTest is AuctionTest {
    function newAuction() returns (uint, uint) {
        return manager.newAuction( seller    // beneficiary
                                 , t1        // selling
                                 , t2        // buying
                                 , 100 * T1  // sell_amount
                                 , 10 * T2   // start_bid
                                 , 1         // min_increase (%)
                                 , 1 years   // ttl
                                 );
    }
    function testNewAuctionEvent() {
        var (id, base) = newAuction();

        expectEventsExact(manager);
        LogNewAuction(id, base);
    }
    function testNewAuction() {
        var (id, base) = newAuction();
        assertEq(id, 1);

        var (beneficiary, selling, buying,
             sell_amount, start_bid, min_increase, ttl) = manager.getAuction(id);

        assertEq(beneficiary, seller);
        assert(selling == ERC20(t1));
        assert(buying == ERC20(t2));
        assertEq(sell_amount, 100 * T1);
        assertEq(start_bid, 10 * T2);
        assertEq(min_increase, 1);
        assertEq(ttl, 1 years);
    }
    function testNewAuctionTransfersToManager() {
        var balance_before = t1.balanceOf(manager);
        newAuction();
        var balance_after = t1.balanceOf(manager);

        assertEq(balance_after - balance_before, 100 * T1);
    }
    function testNewAuctionTransfersFromCreator() {
        var balance_before = t1.balanceOf(this);
        var (id, base) = newAuction();
        var balance_after = t1.balanceOf(this);

        assertEq(balance_before - balance_after, 100 * T1);
    }
    function testNewAuctionlet() {
        var (id, base) = newAuction();

        // can't always know what the auctionlet id is as it is
        // only an internal type. But for the case of a single auction
        // there should be a single auctionlet created with id 1.
        var (auction_id, last_bidder,
             buy_amount, sell_amount) = manager.getAuctionlet(base);

        assertEq(auction_id, id);
        assertEq(last_bidder, seller);
        assertEq(buy_amount, 10 * T2);
        assertEq(sell_amount, 100 * T1);
    }
}

contract BidTest is AuctionTest {
    function newAuction() returns (uint, uint) {
        return manager.newAuction( seller    // beneficiary
                                 , t1        // selling
                                 , t2        // buying
                                 , 100 * T1  // sell_amount
                                 , 10 * T2   // start_bid
                                 , 1         // min_increase (%)
                                 , 1 years   // ttl
                                 );
    }
    function testBidEvent() {
        var (id, base) = newAuction();
        bidder1.doBid(base, 11 * T2, false);
        bidder2.doBid(base, 12 * T2, false);

        expectEventsExact(manager);
        LogNewAuction(id, base);
        LogBid(base);
        LogBid(base);
    }
    function testFailBidUnderMinBid() {
        var (id, base) = newAuction();
        bidder1.doBid(base, 9 * T2, false);
    }
    function testBid() {
        var (id, base) = newAuction();
        bidder1.doBid(base, 11 * T2, false);

        var (auction_id, last_bidder1,
             buy_amount, sell_amount) = manager.getAuctionlet(base);

        assertEq(last_bidder1, bidder1);
        assertEq(buy_amount, 11 * T2);
    }
    function testFailBidTransfer() {
        var (id, base) = newAuction();

        // this should throw as bidder1 only has 1000 t2
        bidder1.doBid(base, 1001 * T2, false);
    }
    function testBidTransfer() {
        var (id, base) = newAuction();

        var bidder1_t2_balance_before = t2.balanceOf(bidder1);
        bidder1.doBid(base, 11 * T2, false);
        var bidder1_t2_balance_after = t2.balanceOf(bidder1);

        var balance_diff = bidder1_t2_balance_before - bidder1_t2_balance_after;
        assertEq(balance_diff, 11 * T2);
    }
    function testBidReturnsToPrevBidder() {
        var (id, base) = newAuction();

        var bidder1_t2_balance_before = t2.balanceOf(bidder1);
        bidder1.doBid(base, 11 * T2, false);
        bidder2.doBid(base, 12 * T2, false);
        var bidder1_t2_balance_after = t2.balanceOf(bidder1);

        var bidder_balance_diff = bidder1_t2_balance_before - bidder1_t2_balance_after;
        assertEq(bidder_balance_diff, 0 * T2);
    }
    function testFailBidExpired() {
        var (id, base) = newAuction();
        bidder1.doBid(base, 11 * T2, false);

        // force expiry
        manager.addTime(2 years);

        bidder2.doBid(base, 12 * T2, false);
    }
    function testBaseDoesNotExpire() {
        var (id, base) = newAuction();

        // push past the base auction ttl
        manager.addTime(2 years);

        // this should succeed as there are no real bidders
        bidder1.doBid(base, 11 * T2, false);
    }
    function testBidTransfersBenefactor() {
        var (id, base) = newAuction();

        var balance_before = t2.balanceOf(seller);
        bidder1.doBid(base, 40 * T2, false);
        var balance_after = t2.balanceOf(seller);

        assertEq(balance_after - balance_before, 40 * T2);
    }
    function testBidTransfersToDistinctBeneficiary() {
        var (id, base) = manager.newAuction(bidder2, t1, t2, 100 * T1, 0 * T2, 1, 1 years);

        var balance_before = t2.balanceOf(bidder2);
        bidder1.doBid(base, 10 * T2, false);
        var balance_after = t2.balanceOf(bidder2);

        assertEq(balance_after - balance_before, 10 * T2);
    }
}

contract MultipleAuctionTest is AuctionTest {
    function newAuction() returns (uint, uint) {
        return manager.newAuction( seller    // beneficiary
                                 , t1        // selling
                                 , t2        // buying
                                 , 100 * T1  // sell_amount
                                 , 10 * T2   // start_bid
                                 , 1         // min_increase (%)
                                 , 1 years   // ttl
                                 );
    }
    function testMultipleNewAuctions() {
        // auction manager should be able to manage multiple auctions
        t2.transfer(seller, 200 * T2);
        seller.doApprove(manager, 200 * T2, t2);

        var t1_balance_before = t1.balanceOf(this);
        var t2_balance_before = t2.balanceOf(this);

        var (id1, base1) = newAuction();
        // flip tokens around
        var (id2, base2) = manager.newAuction(seller, t2, t1, 100 * T2, 10 * T1, 1, 1 years);

        assertEq(id1, 1);
        assertEq(id2, 2);

        assertEq(t1_balance_before - t1.balanceOf(this), 100 * T1);
        assertEq(t2_balance_before - t2.balanceOf(this), 100 * T2);

        var (beneficiary, selling, buying,
             sell_amount, start_bid, min_increase, ttl) = manager.getAuction(id2);

        assertEq(beneficiary, seller);
        assert(selling == ERC20(t2));
        assert(buying == ERC20(t1));
        assertEq(sell_amount, 100 * T2);
        assertEq(start_bid, 10 * T1);
        assertEq(min_increase, 1);
        assertEq(ttl, 1 years);
    }
    function testMultipleAuctionsBidTransferToBenefactor() {
        var (id1, base1) = newAuction();
        var (id2, base2) = newAuction();

        var seller_t2_balance_before = t2.balanceOf(seller);

        bidder1.doBid(base1, 11 * T2, false);
        bidder2.doBid(base2, 11 * T2, false);

        var seller_t2_balance_after = t2.balanceOf(seller);

        var diff_t2 = seller_t2_balance_after - seller_t2_balance_before;

        assertEq(diff_t2, 22 * T2);
    }
    function testMultipleAuctionsTransferFromCreator() {
        var balance_before = t1.balanceOf(this);

        var (id1, base1) = newAuction();
        var (id2, base2) = newAuction();

        var balance_after = t1.balanceOf(this);

        assertEq(balance_before - balance_after, 200 * T1);
    }
}

contract MinBidIncreaseTest is AuctionTest {
    function newAuction() returns (uint, uint) {
        return manager.newAuction( seller    // beneficiary
                                 , t1        // selling
                                 , t2        // buying
                                 , 100 * T1  // sell_amount
                                 , 10 * T2   // start_bid
                                 , 20        // min_increase (%)
                                 , 1 years   // ttl
                                 );
    }
    function testFailFirstBidEqualStartBid() {
        var (id, base) = newAuction();
        bidder1.doBid(base, 10 * T2, false);
    }
    function testFailSubsequentBidEqualLastBid() {
        var (id, base) = newAuction();
        bidder1.doBid(base, 13 * T2, false);
        bidder2.doBid(base, 13 * T2, false);
    }
    function testFailFirstBidLowerThanMinIncrease() {
        var (id, base) = newAuction();
        bidder1.doBid(base, 11 * T2, false);
    }
    function testFailSubsequentBidLowerThanMinIncrease() {
        var (id, base) = newAuction();
        bidder1.doBid(base, 12 * T2, false);
        bidder2.doBid(base, 13 * T2, false);
    }
}

contract MultipleBeneficiariesTest is AuctionTest {
    function testNewAuction() {
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary1;

        uint[] memory payouts = new uint[](1);
        payouts[0] = INFINITY;

        var (id1, base1) = manager.newAuction(beneficiary1, t1, t2, 100 * T1, 0 * T2, 1, 1 years);
        var (id2, base2) = manager.newAuction(beneficiaries, payouts, t1, t2, 100 * T1, 0 * T2, 1, 1 years);

        var (beneficiary, selling, buying,
             sell_amount, start_bid, min_increase, expiration) = manager.getAuction(id1);

        assertEq(beneficiary, beneficiary1);

        (beneficiary, selling, buying,
         sell_amount, start_bid, min_increase, expiration) = manager.getAuction(id2);

        assertEq(beneficiary, beneficiary1);
    }
    function testFailUnequalPayoutsLength() {
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = beneficiary1;

        uint[] memory payouts = new uint[](1);
        payouts[0] = INFINITY;

        var (id2, base2) = manager.newAuction(beneficiaries, payouts, t1, t2, 100 * T1, 0 * T2, 1, 1 years);
    }
    function testFailNonSummingPayouts() {
        address[] memory beneficiaries = new address[](3);
        beneficiaries[0] = beneficiary1;

        uint[] memory payouts = new uint[](3);
        payouts[0] = 0;
        payouts[1] = 1;
        payouts[2] = 2;

        var (id2, base2) = manager.newAuction(beneficiaries, payouts, t1, t2, 100 * T1, 0 * T2, 1, 1 years);
    }
    function testFailFirstPayoutLessThanStartBid() {
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;

        uint[] memory payouts = new uint[](2);
        payouts[0] = 10 * T2;
        payouts[1] = INFINITY - 10 * T2;

        var (id, base) = manager.newAuction(beneficiaries, payouts, t1, t2, 100 * T1, 50 * T2, 1, 1 years);
    }
    function testPayoutFirstBeneficiary() {
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;

        uint[] memory payouts = new uint[](2);
        payouts[0] = 10 * T2;
        payouts[1] = INFINITY - 10 * T2;

        var (id, base) = manager.newAuction(beneficiaries, payouts, t1, t2, 100 * T1, 5 * T2, 1, 1 years);

        var balance_before = t2.balanceOf(beneficiary1);
        bidder1.doBid(id, 30 * T2, false);
        var balance_after = t2.balanceOf(beneficiary1);

        assertEq(balance_after - balance_before, 10 * T2);
    }
    function testPayoutSecondBeneficiary() {
        var balance_before = t2.balanceOf(beneficiary2);
        testPayoutFirstBeneficiary();
        var balance_after = t2.balanceOf(beneficiary2);

        assertEq(balance_after - balance_before, 20 * T2);
    }
}

contract AssertionTest is DSTest, Assertive() {
    function testAssert() {
        assert(2 > 1);
    }
    function testFailAssert() {
        assert(2 < 1);
    }
    function testIncreasingNoop() {
        uint[] memory array = new uint[](1);
        array[0] = 1;
        assertIncreasing(array);
    }
    function testIncreasing() {
        uint[] memory array = new uint[](2);
        array[0] = 1;
        array[1] = 2;
        assertIncreasing(array);
    }
    function testFailIncreasing() {
        uint[] memory array = new uint[](2);
        array[0] = 2;
        array[1] = 1;
        assertIncreasing(array);
    }
}

contract MathTest is DSTest, MathUser {
    uint[] array;
    function setUp() {
        uint[] memory _array = new uint[](3);
        _array[0] = 1;
        _array[1] = 3;
        _array[2] = 0;
        array = _array;
    }
    function testFlat() {
        assertEq(0, zeroSub(1, 2));
        assertEq(1, zeroSub(2, 1));
    }
    function testCumSum() {
        uint[] memory expected = new uint[](3);
        expected[0] = 1;
        expected[1] = 4;
        expected[2] = 4;

        var found = cumsum(array);
        for (uint i = 0; i < array.length; i++) {
            assertEq(expected[i], found[i]);
        }
    }
    function testSum() {
        assertEq(4, sum(array));
    }
    function testSumEquivalentCumSum() {
        assertEq(cumsum(array)[2], sum(array));
    }
}

contract ClaimTest is AuctionTest {
    function newAuction() returns (uint, uint) {
        return manager.newAuction( beneficiary1  // beneficiary
                                 , t1            // selling
                                 , t2            // buying
                                 , 100 * T1      // sell_amount
                                 , 10 * T2       // start_bid
                                 , 1             // min_increase (%)
                                 , 1 years       // ttl
                                 );
    }
    function testClaimTransfersBidder() {
        var (id, base) = newAuction();
        bidder1.doBid(base, 11 * T2, false);
        // force expiry
        manager.addTime(2 years);

        var balance_before = t1.balanceOf(bidder1);
        // n.b. anyone can force claim, not just the bidder
        bidder1.doClaim(base);
        var balance_after = t1.balanceOf(bidder1);

        assertEq(balance_after - balance_before, 100 * T1);
    }
    function testClaimNonParty() {
        var (id, base) = newAuction();
        bidder1.doBid(base, 11 * T2, false);
        manager.addTime(2 years);

        var balance_before = t1.balanceOf(bidder1);
        // n.b. anyone can force claim, not just the bidder
        bidder2.doClaim(base);
        var balance_after = t1.balanceOf(bidder1);

        assertEq(balance_after - balance_before, 100 * T1);
    }
    function testFailClaimProceedingsPreExpiration() {
        // bidders cannot claim their auctionlet until the auction has
        // expired.
        var (id, base) = newAuction();
        bidder1.doBid(base, 11 * T2, false);
        bidder1.doClaim(base);
    }
    function testFailBidderClaimAgain() {
        // bidders should not be able to claim their auctionlet more than once
        var (id1, base1) = newAuction();
        var (id2, base2) = newAuction();

        // create bids on two different auctions so that the manager has
        // enough funds for us to attempt to withdraw all at once
        bidder1.doBid(base1, 11 * T2, false);
        bidder2.doBid(base2, 11 * T2, false);

        // force expiry
        manager.addTime(2 years);

        // now attempt to claim the proceedings from the first
        // auctionlet twice
        bidder1.doClaim(base1);
        bidder1.doClaim(base1);
    }
    function testFailClaimBase() {
        // base auctionlets should not be claimable
        var (id, base) = newAuction();
        manager.addTime(2 years);

        // The beneficiary is set as the last bidder on the base auctionlet,
        // so that they get transferred the start bid. They should not be able
        // to claim the base auctionlet.
        beneficiary1.doClaim(base);
    }
    function testFailClaimBaseNonParty() {
        // base auctionlets should not be claimable
        var (id, base) = newAuction();
        manager.addTime(2 years);

        manager.claim(base);  // doesn't matter who calls claim
    }
}

// New auctions have an optional ttl parameter that sets a global
// auction expiry (across all of its auctionlets). After this expiry, no
// more bids can be placed and bid winners can claim their bids. In
// contrast to the per-auctionlet expiry (which does not apply to unbid
// collateral), following the auction expiry the collateral can be
// claimed (and sent to the beneficiary) even if there have been no bids.
contract ExpiryTest is AuctionTest {
    function newAuction(uint ttl, uint expiration)
        returns (uint, uint)
    {
        return manager.newAuction( beneficiary1  // beneficiary
                                 , t1            // selling
                                 , t2            // buying
                                 , 100 * T1      // sell_amount
                                 , 0             // start_bid
                                 , 0             // min_increase (%)
                                 , ttl
                                 , expiration
                                 );
    }
    function testExpiryTimes() {
        var (id, base) = newAuction({ ttl:        20 days
                                    , expiration: now + 10 days });

        assert(!manager.isExpired(base));
        manager.addTime(8 days);
        assert(!manager.isExpired(base));
        manager.addTime(8 days);
        assert(manager.isExpired(base));
        manager.addTime(8 days);
        assert(manager.isExpired(base));
    }
    function testFailBidPostAuctionExpiryPreAuctionletExpiry() {
        var (id, base) = newAuction({ ttl:        20 days
                                    , expiration: now + 10 days });

        manager.addTime(15 days);

        // fails because auction has expired
        bidder1.doBid(base, 1 * T2, false);
    }
    function testFailBidPostAuctionletExpiryPostAuctionExpiry() {
        var (id, base) = newAuction({ ttl:        20 days
                                    , expiration: now + 10 days });

        bidder1.doBid(base, 1 * T2, false);
        manager.addTime(25 days);

        bidder2.doBid(base, 2 * T2, false);
    }
    function testFailSplitPostAuctionExpiryPreAuctionletExpiry() {
        var (id, base) = newAuction({ ttl:        20 days
                                    , expiration: now + 10 days });

        manager.addTime(15 days);

        bidder1.doBid(base, 1 * T2, 50 * T1, false);
    }
    function testFailSplitPostAuctionletExpiryPostAuctionExpiry() {
        var (id, base) = newAuction({ ttl:        20 days
                                    , expiration: now + 10 days });

        bidder1.doBid(base, 1 * T2, false);
        manager.addTime(25 days);

        bidder2.doBid(base, 1 * T2, 50 * T1, false);
    }
    function testClaimBasePostAuctionExpiryPreAuctionletExpiry() {
        var (id, base) = newAuction({ ttl:        20 days
                                    , expiration: now + 10 days });

        manager.addTime(15 days);

        var balance_before = t1.balanceOf(beneficiary1);
        manager.claim(base);
        assertEq(t1.balanceOf(beneficiary1) - balance_before, 100 * T1);
    }
    function testClaimBasePostAuctionExpiryPostAuctionletExpiry() {
        var (id, base) = newAuction({ ttl:        20 days
                                    , expiration: now + 10 days });

        manager.addTime(25 days);

        var balance_before = t1.balanceOf(beneficiary1);
        manager.claim(base);
        assertEq(t1.balanceOf(beneficiary1) - balance_before, 100 * T1);
    }
    function testClaimPostAuctionExpiryPostAuctionletExpiry() {
        var (id, base) = newAuction({ ttl:        20 days
                                    , expiration: now + 10 days });

        bidder1.doBid(base, 1 * T2, false);
        manager.addTime(15 days);

        var balance_before = t1.balanceOf(bidder1);
        manager.claim(base);
        assertEq(t1.balanceOf(bidder1) - balance_before, 100 * T1);
    }
    function testClaimPostAuctionExpiryPreAuctionletExpiry() {
        var (id, base) = newAuction({ ttl:        20 days
                                    , expiration: now + 10 days });

        bidder1.doBid(base, 1 * T2, false);
        manager.addTime(25 days);

        var balance_before = t1.balanceOf(bidder1);
        manager.claim(base);
        assertEq(t1.balanceOf(bidder1) - balance_before, 100 * T1);
    }
}
