import 'dapple/test.sol';
import 'erc20/base.sol';
import 'auction_manager.sol';

contract TestableManager is AuctionManager {
    uint public debug_timestamp;

    function getTime() public constant returns (uint) {
        return debug_timestamp;
    }
    function setTime(uint timestamp) {
        debug_timestamp = timestamp;
    }
}

contract AuctionTester is Tester {
    TestableManager manager;
    function bindManager(TestableManager _manager) {
        _target(_manager);
        manager = TestableManager(_t);
    }
    function doApprove(address spender, uint value, ERC20 token) {
        token.approve(spender, value);
    }
    function doBid(uint auctionlet_id, uint bid_how_much)
    {
        return manager.bid(auctionlet_id, bid_how_much);
    }
    function doClaim(uint id) {
        return manager.claim(id);
    }
    function doReclaim(uint id) {
        return manager.reclaim(id);
    }
}

contract AuctionManagerTest is Test, EventfulAuction, EventfulManager {
    TestableManager manager;
    AuctionTester seller;
    AuctionTester bidder1;
    AuctionTester bidder2;

    ERC20 t1;
    ERC20 t2;

    // use prime numbers to avoid coincidental collisions
    uint constant T1 = 5 ** 12;
    uint constant T2 = 7 ** 10;

    function setUp() {
        manager = new TestableManager();
        manager.setTime(block.timestamp);

        var million = 10 ** 6;

        t1 = new ERC20Base(million * T1);
        t2 = new ERC20Base(million * T2);

        seller = new AuctionTester();
        seller.bindManager(manager);

        t1.transfer(seller, 200 * T1);
        seller.doApprove(manager, 200 * T1, t1);

        bidder1 = new AuctionTester();
        bidder1.bindManager(manager);

        t2.transfer(bidder1, 1000 * T2);
        bidder1.doApprove(manager, 1000 * T2, t2);

        bidder2 = new AuctionTester();
        bidder2.bindManager(manager);

        t2.transfer(bidder2, 1000 * T2);
        bidder2.doApprove(manager, 1000 * T2, t2);

        t1.transfer(this, 1000 * T1);
        t2.transfer(this, 1000 * T2);
        t1.approve(manager, 1000 * T1);
        t2.approve(manager, 1000 * T2);
    }
    function testSetUp() {
        assertEq(t2.balanceOf(bidder1), 1000 * T2);
        assertEq(t2.allowance(bidder1, manager), 1000 * T2);
    }
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
    function testNewAuctionEvent() {
        var (id, base) = newAuction();

        expectEventsExact(manager);
        NewAuction(id, base);
    }
    function testBidEvent() {
        var (id, base) = newAuction();
        bidder1.doBid(base, 11 * T2);
        bidder2.doBid(base, 12 * T2);

        expectEventsExact(manager);
        NewAuction(id, base);
        Bid(base);
        Bid(base);
    }
    function testNewAuction() {
        var (id, base) = newAuction();
        assertEq(id, 1);

        var (beneficiary, selling, buying,
             sell_amount, start_bid, min_increase, expiration) = manager.getAuction(id);

        assertEq(beneficiary, seller);
        assertTrue(selling == t1);
        assertTrue(buying == t2);
        assertEq(sell_amount, 100 * T1);
        assertEq(start_bid, 10 * T2);
        assertEq(min_increase, 1 * T2);
        assertEq(expiration, manager.getTime() + 1 years);
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
    function testFailBidUnderMinBid() {
        var (id, base) = newAuction();
        bidder1.doBid(base, 9 * T2);
    }
    function testFailBidUnderMinIncrease() {
        var (id, base) = newAuction();
        bidder1.doBid(base, 10 * T2);
        bidder2.doBid(base, 11 * T2);
    }
    function testBid() {
        var (id, base) = newAuction();
        bidder1.doBid(base, 11 * T2);

        var (auction_id, last_bidder1,
             buy_amount, sell_amount) = manager.getAuctionlet(base);

        assertEq(last_bidder1, bidder1);
        assertEq(buy_amount, 11 * T2);
    }
    function testFailBidTransfer() {
        var (id, base) = newAuction();

        // this should throw as bidder1 only has 1000 t2
        bidder1.doBid(base, 1001 * T2);
    }
    function testBidTransfer() {
        var (id, base) = newAuction();

        var bidder1_t2_balance_before = t2.balanceOf(bidder1);
        bidder1.doBid(base, 11 * T2);
        var bidder1_t2_balance_after = t2.balanceOf(bidder1);

        var balance_diff = bidder1_t2_balance_before - bidder1_t2_balance_after;
        assertEq(balance_diff, 11 * T2);
    }
    function testBidReturnsToPrevBidder() {
        var (id, base) = newAuction();

        var bidder1_t2_balance_before = t2.balanceOf(bidder1);
        bidder1.doBid(base, 11 * T2);
        bidder2.doBid(base, 12 * T2);
        var bidder1_t2_balance_after = t2.balanceOf(bidder1);

        var bidder_balance_diff = bidder1_t2_balance_before - bidder1_t2_balance_after;
        assertEq(bidder_balance_diff, 0 * T2);
    }
    function testFailBidExpired() {
        var (id, base) = newAuction();
        bidder1.doBid(base, 11 * T2);

        // force expiry
        manager.setTime(manager.getTime() + 2 years);

        bidder2.doBid(base, 12 * T2);
    }
    function testBidTransfersBenefactor() {
        var (id, base) = newAuction();

        var balance_before = t2.balanceOf(seller);
        bidder1.doBid(base, 40 * T2);
        var balance_after = t2.balanceOf(seller);

        assertEq(balance_after - balance_before, 40 * T2);
    }
    function testClaimTransfersBidder() {
        var bidder_t2_balance_before = t2.balanceOf(bidder1);
        var bidder_t1_balance_before = t1.balanceOf(bidder1);

        var (id, base) = newAuction();
        bidder1.doBid(base, 11 * T2);

        // force expiry
        manager.setTime(manager.getTime() + 2 years);

        // n.b. anyone can force claim, not just the bidder
        manager.claim(1);

        var bidder_t2_balance_after = t2.balanceOf(bidder1);
        var bidder_t1_balance_after = t1.balanceOf(bidder1);

        var diff_t1 = bidder_t1_balance_after - bidder_t1_balance_before;
        var diff_t2 = bidder_t2_balance_before - bidder_t2_balance_after;

        assertEq(diff_t2, 11 * T2);
        assertEq(diff_t1, 100 * T1);
    }
    function testFailClaimNonParty() {
        var (id, base) = newAuction();
        bidder1.doBid(base, 11 * T2);
        // bidder2 is not party to the auction and should not be able to
        // initiate a claim
        bidder2.doClaim(1);
    }
    function testFailClaimProceedingsPreExpiration() {
        // bidders cannot claim their auctionlet until the auction has
        // expired.
        var (id, base) = newAuction();
        bidder1.doBid(base, 11 * T2);
        bidder1.doClaim(1);
    }
    function testMultipleNewAuctions() {
        // auction manager should be able to manage multiple auctions
        t2.transfer(seller, 200 * T2);
        seller.doApprove(manager, 200 * T2, t2);

        var t1_balance_before = t1.balanceOf(this);
        var t2_balance_before = t2.balanceOf(this);

        var (id1, base1) = newAuction();
        // flip tokens around
        var (id2, base2) = manager.newAuction(seller, t2, t1, 100 * T2, 10 * T1, 1 * T1, 1 years);

        assertEq(id1, 1);
        assertEq(id2, 2);

        assertEq(t1_balance_before - t1.balanceOf(this), 100 * T1);
        assertEq(t2_balance_before - t2.balanceOf(this), 100 * T2);

        var (beneficiary, selling, buying,
             sell_amount, start_bid, min_increase, expiration) = manager.getAuction(id2);

        assertEq(beneficiary, seller);
        assertTrue(selling == t2);
        assertTrue(buying == t1);
        assertEq(sell_amount, 100 * T2);
        assertEq(start_bid, 10 * T1);
        assertEq(min_increase, 1 * T1);
        assertEq(expiration, manager.getTime() + 1 years);
    }
    function testMultipleAuctionsBidTransferToBenefactor() {
        var (id1, base1) = newAuction();
        var (id2, base2) = newAuction();

        var seller_t2_balance_before = t2.balanceOf(seller);

        bidder1.doBid(base1, 11 * T2);
        bidder2.doBid(base2, 11 * T2);

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
    function testFailBidderClaimAgain() {
        // bidders should not be able to claim their auctionlet more than once

        // create an auction that expires immediately
        var (id1, base1) = newAuction();
        var (id2, base2) = newAuction();

        // create bids on two different auctions so that the manager has
        // enough funds for us to attempt to withdraw all at once
        bidder1.doBid(base1, 11 * T2);
        bidder2.doBid(base2, 11 * T2);

        // now attempt to claim the proceedings from the first
        // auctionlet twice
        bidder1.doClaim(1);
        bidder1.doClaim(1);
    }
    function testReclaimAfterExpiry() {
        // the seller should be able to reclaim any unbid on
        // sell token after the auction has expired.
        var (id, base) = newAuction();

        // force expiry
        manager.setTime(manager.getTime() + 2 years);

        var balance_before = t1.balanceOf(this);
        manager.reclaim(id);
        var balance_after = t1.balanceOf(this);

        assertEq(balance_after - balance_before, 100 * T1);
    }
    function testFailReclaimBeforeExpiry() {
        var (id, base) = newAuction();
        seller.doReclaim(id);
    }
    function testBidTransfersToDistinctBeneficiary() {
        var (id, base) = manager.newAuction(bidder2, t1, t2, 100 * T1, 0 * T2, 1 * T2, 1 years);

        var balance_before = t2.balanceOf(bidder2);
        bidder1.doBid(base, 10 * T2);
        var balance_after = t2.balanceOf(bidder2);

        assertEq(balance_after - balance_before, 10 * T2);
    }
    function testReclaimOnlyOnce() {
        var (id1, base1) = newAuction();
        var (id2, base2) = newAuction();

        // force expiry
        manager.setTime(manager.getTime() + 2 years);

        manager.reclaim(id1);
        var balance_before = t1.balanceOf(this);
        manager.reclaim(id1);
        var balance_after = t1.balanceOf(this);

        assertEq(balance_after, balance_before);
    }
}
