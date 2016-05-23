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
}

contract AuctionManagerTest is Test {
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
    }
    function testSetUp() {
        assertEq(t2.balanceOf(bidder1), 1000 * T2);
        assertEq(t2.allowance(bidder1, manager), 1000 * T2);
    }
    function testNewAuction() {
        var balance_before = t1.balanceOf(seller);
        var (id, base) = manager.newAuction(seller,  // beneficiary
                                            t1,      // selling
                                            t2,      // buying
                                            100 * T1,// sell amount (t1)
                                            0 * T2,  // minimum bid (t2)
                                            1 * T2,  // minimum increase
                                            1 years  // duration
                                           );
        assertEq(id, 1);
        var balance_after = t1.balanceOf(seller);

        var (beneficiary, selling, buying,
             sell_amount, min_bid, min_increase, expiration) = manager.getAuction(id);

        assertEq(beneficiary, seller);
        assertTrue(selling == t1);
        assertTrue(buying == t2);
        assertEq(sell_amount, 100 * T1);
        assertEq(min_bid, 0 * T2);
        assertEq(min_increase, 1 * T2);
        assertEq(expiration, manager.getTime() + 1 years);

        var balance_diff = balance_before - balance_after;
        assertEq(balance_diff, 100 * T1);
    }
    function testNewAuctionlet() {
        var (id, base) = manager.newAuction(seller, t1, t2, 100 * T1, 0 * T2, 1 * T2, 1 years);

        // can't always know what the auctionlet id is as it is
        // only an internal type. But for the case of a single auction
        // there should be a single auctionlet created with id 1.
        var (auction_id, last_bidder1,
             last_bid, quantity) = manager.getAuctionlet(base);

        assertEq(auction_id, id);
        assertEq(last_bidder1, 0);
        assertEq(last_bid, 0 * T2);
        assertEq(quantity, 100 * T1);
    }
    function testFailBidUnderMinBid() {
        var (base, id) = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        bidder1.doBid(1, 9 * T2);
    }
    function testFailBidUnderMinIncrease() {
        var (base, id) = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 2 * T2, 1 years);
        bidder1.doBid(1, 10 * T2);
        bidder2.doBid(1, 11 * T2);
    }
    function testBid() {
        var (base, id) = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        bidder1.doBid(1, 11 * T2);

        var (auction_id, last_bidder1,
             last_bid, quantity) = manager.getAuctionlet(base);

        assertEq(last_bidder1, bidder1);
        assertEq(last_bid, 11 * T2);
    }
    function testFailBidTransfer() {
        var (base, id) = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);

        // this should throw as bidder1 only has 1000 t2
        bidder1.doBid(1, 1001 * T2);
    }
    function testBidTransfer() {
        var (base, id) = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);

        var bidder1_t2_balance_before = t2.balanceOf(bidder1);
        bidder1.doBid(1, 11 * T2);
        var bidder1_t2_balance_after = t2.balanceOf(bidder1);

        var balance_diff = bidder1_t2_balance_before - bidder1_t2_balance_after;
        assertEq(balance_diff, 11 * T2);
    }
    function testBidReturnsToPrevBidder() {
        var (base, id) = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);

        var bidder1_t2_balance_before = t2.balanceOf(bidder1);
        var manager_t2_balance_before = t2.balanceOf(manager);
        bidder1.doBid(1, 11 * T2);
        bidder2.doBid(1, 12 * T2);
        var bidder1_t2_balance_after = t2.balanceOf(bidder1);
        var manager_t2_balance_after = t2.balanceOf(manager);

        var bidder_balance_diff = bidder1_t2_balance_before - bidder1_t2_balance_after;
        var manager_balance_diff = manager_t2_balance_after - manager_t2_balance_before;
        assertEq(bidder_balance_diff, 0 * T2);
        assertEq(manager_balance_diff, 12 * T2);
    }
    function testFailBidExpired() {
        manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        bidder1.doBid(1, 11 * T2);

        // force expiry
        manager.setTime(manager.getTime() + 2 years);

        bidder2.doBid(1, 12 * T2);
    }
    function testClaimTransfersBenefactor() {
        var seller_t2_balance_before = t2.balanceOf(seller);
        var seller_t1_balance_before = t1.balanceOf(seller);

        var (base, id) = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        bidder1.doBid(1, 40 * T2);
        seller.doClaim(id);

        var seller_t2_balance_after = t2.balanceOf(seller);
        var seller_t1_balance_after = t1.balanceOf(seller);

        var diff_t1 = seller_t1_balance_before - seller_t1_balance_after;
        var diff_t2 = seller_t2_balance_after - seller_t2_balance_before;

        assertEq(diff_t2, 40 * T2);
        assertEq(diff_t1, 100 * T1);
    }
    function testClaimAfterDoubleBid() {
        var seller_t2_balance_before = t2.balanceOf(seller);
        var seller_t1_balance_before = t1.balanceOf(seller);

        var (base, id) = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        bidder1.doBid(1, 40 * T2);
        bidder2.doBid(1, 60 * T2);
        seller.doClaim(id);

        var seller_t2_balance_after = t2.balanceOf(seller);
        var seller_t1_balance_after = t1.balanceOf(seller);

        var diff_t1 = seller_t1_balance_before - seller_t1_balance_after;
        var diff_t2 = seller_t2_balance_after - seller_t2_balance_before;

        assertEq(diff_t2, 60 * T2);
        assertEq(diff_t1, 100 * T1);
    }
    function testBenefactorClaimLogged() {
        var (base, id) = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        bidder1.doBid(1, 11 * T2);
        seller.doClaim(id);

        var seller_t1_balance_before = t1.balanceOf(seller);
        var seller_t2_balance_before = t2.balanceOf(seller);

        // calling claim again should not do anything as there
        // have been no new bids
        seller.doClaim(id);

        var seller_t1_balance_after = t1.balanceOf(seller);
        var seller_t2_balance_after = t2.balanceOf(seller);

        var diff_t1 = seller_t1_balance_before - seller_t1_balance_after;
        var diff_t2 = seller_t2_balance_after - seller_t2_balance_before;

        assertEq(diff_t2, 0);
        assertEq(diff_t1, 0);
    }
    function testClaimTransfersBidder() {
        var bidder_t2_balance_before = t2.balanceOf(bidder1);
        var bidder_t1_balance_before = t1.balanceOf(bidder1);

        var (base, id) = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        bidder1.doBid(1, 11 * T2);

        // force expiry
        manager.setTime(manager.getTime() + 2 years);

        bidder1.doClaim(1);

        var bidder_t2_balance_after = t2.balanceOf(bidder1);
        var bidder_t1_balance_after = t1.balanceOf(bidder1);

        var diff_t1 = bidder_t1_balance_after - bidder_t1_balance_before;
        var diff_t2 = bidder_t2_balance_before - bidder_t2_balance_after;

        assertEq(diff_t2, 11 * T2);
        assertEq(diff_t1, 100 * T1);
    }
    function testFailClaimNonParty() {
        var (base, id) = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        bidder1.doBid(1, 11 * T2);
        // bidder2 is not party to the auction and should not be able to
        // initiate a claim
        bidder2.doClaim(1);
    }
    function testFailClaimProceedingsPreExpiration() {
        // bidders cannot claim their auctionlet until the auction has
        // expired.
        var (base, id) = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        bidder1.doBid(1, 11 * T2);
        bidder1.doClaim(1);
    }
    function testMultipleNewAuctions() {
        // auction manager should be able to manage multiple auctions
        t2.transfer(seller, 200 * T2);
        seller.doApprove(manager, 200 * T2, t2);

        var t1_balance_before = t1.balanceOf(seller);
        var t2_balance_before = t2.balanceOf(seller);

        var (id1, base1) = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        var (id2, base2) = manager.newAuction(seller, t2, t1, 100 * T2, 10 * T1, 1 * T1, 1 years);

        assertEq(id1, 1);
        assertEq(id2, 2);

        assertEq(t1_balance_before - t1.balanceOf(seller), 100 * T1);
        assertEq(t2_balance_before - t2.balanceOf(seller), 100 * T2);

        var (beneficiary, selling, buying,
             sell_amount, min_bid, min_increase, expiration) = manager.getAuction(id2);

        assertEq(beneficiary, seller);
        assertTrue(selling == t2);
        assertTrue(buying == t1);
        assertEq(sell_amount, 100 * T2);
        assertEq(min_bid, 10 * T1);
        assertEq(min_increase, 1 * T1);
        assertEq(expiration, manager.getTime() + 1 years);
    }
    function testMultipleAuctionClaims() {
        manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);

        var seller_t2_balance_before = t2.balanceOf(seller);
        var seller_t1_balance_before = t1.balanceOf(seller);

        var (base, id) = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        bidder1.doBid(2, 11 * T2);
        seller.doClaim(id);

        var seller_t2_balance_after = t2.balanceOf(seller);
        var seller_t1_balance_after = t1.balanceOf(seller);

        var diff_t1 = seller_t1_balance_before - seller_t1_balance_after;
        var diff_t2 = seller_t2_balance_after - seller_t2_balance_before;

        assertEq(diff_t2, 11 * T2);
        assertEq(diff_t1, 100 * T1);
    }
    function testFailBidderClaimAgain() {
        // bidders should not be able to claim their auctionlet more than once

        // create an auction that expires immediately
        var (id1, base1) = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 0 years);
        var (id2, base2) = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 0 years);

        // create bids on two different auctions so that the manager has
        // enough funds for us to attempt to withdraw all at once
        bidder1.doBid(1, 11 * T2);
        bidder2.doBid(2, 11 * T2);

        // now attempt to claim the proceedings from the first
        // auctionlet twice
        bidder1.doClaim(1);
        bidder1.doClaim(1);
    }
}
