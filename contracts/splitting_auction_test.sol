import 'dapple/test.sol';
import 'erc20/base.sol';
import 'splitting_auction.sol';


contract Manager is SplittableAuctionManager {
    uint public debug_timestamp;

    function getTime() public constant returns (uint) {
        return debug_timestamp;
    }
    function setTime(uint timestamp) {
        debug_timestamp = timestamp;
    }
}

contract AuctionTester is Tester {
    function doApprove(address spender, uint value, ERC20 token) {
        token.approve(spender, value);
    }
    function doBid(Manager manager, uint auctionlet_id, uint bid_how_much)
    {
        return manager.bid(auctionlet_id, bid_how_much);
    }
    function doBid(Manager manager, uint auctionlet_id, uint bid_how_much, uint quantity)
        returns (uint, uint)
    {
        return manager.bid(auctionlet_id, bid_how_much, quantity);
    }
    function doClaim(Manager manager, uint id) {
        return manager.claim(id);
    }
}

contract SplittingAuctionManagerTest is Test {
    Manager manager;
    AuctionTester seller;
    AuctionTester bidder1;
    AuctionTester bidder2;

    ERC20 t1;
    ERC20 t2;

    uint constant T1 = 10 ** 12;
    uint constant T2 = 10 ** 10;

    function setUp() {
        manager = new Manager();
        manager.setTime(block.timestamp);

        var million = 10 ** 6;

        t1 = new ERC20Base(million * T1);
        t2 = new ERC20Base(million * T2);

        seller = new AuctionTester();
        seller._target(manager);

        t1.transfer(seller, 200 * T1);
        seller.doApprove(manager, 200 * T1, t1);

        bidder1 = new AuctionTester();
        bidder1._target(manager);

        t2.transfer(bidder1, 1000 * T2);
        bidder1.doApprove(manager, 1000 * T2, t2);

        bidder2 = new AuctionTester();
        bidder2._target(manager);

        t2.transfer(bidder2, 1000 * T2);
        bidder2.doApprove(manager, 1000 * T2, t2);
    }
    function testSetUp() {
        assertEq(t2.balanceOf(bidder1), 1000 * T2);
        assertEq(t2.allowance(bidder1, manager), 1000 * T2);
    }
    function testNewAuction() {
        var balance_before = t1.balanceOf(seller);
        var id = manager.newAuction(seller,  // beneficiary
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
        var id = manager.newAuction(seller, t1, t2, 100 * T1, 0 * T2, 1 * T2, 1 years);

        // can't always know what the auctionlet id is as it is
        // only an internal type. But for the case of a single auction
        // there should be a single auctionlet created with id 1.
        var (auction_id, last_bidder1,
             last_bid, quantity) = manager.getAuctionlet(1);

        assertEq(auction_id, id);
        assertEq(last_bidder1, 0);
        assertEq(last_bid, 0 * T2);
        assertEq(quantity, 100 * T1);
    }
    function testFailBidUnderMinBid() {
        var id = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        bidder1.doBid(manager, 1, 9 * T2);
    }
    function testFailBidUnderMinIncrease() {
        var id = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 2 * T2, 1 years);
        bidder1.doBid(manager, 1, 10 * T2);
        bidder2.doBid(manager, 1, 11 * T2);
    }
    function testBid() {
        var id = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        bidder1.doBid(manager, 1, 11 * T2);

        var (auction_id, last_bidder1,
             last_bid, quantity) = manager.getAuctionlet(1);

        assertEq(last_bidder1, bidder1);
        assertEq(last_bid, 11 * T2);
    }
    function testFailBidTransfer() {
        var id = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);

        // this should throw as bidder1 only has 1000 t2
        bidder1.doBid(manager, 1, 1001 * T2);
    }
    function testBidTransfer() {
        var id = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);

        var bidder1_t2_balance_before = t2.balanceOf(bidder1);
        bidder1.doBid(manager, 1, 11 * T2);
        var bidder1_t2_balance_after = t2.balanceOf(bidder1);

        var balance_diff = bidder1_t2_balance_before - bidder1_t2_balance_after;
        assertEq(balance_diff, 11 * T2);
    }
    function testBidReturnsToPrevBidder() {
        var id = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);

        var bidder1_t2_balance_before = t2.balanceOf(bidder1);
        var manager_t2_balance_before = t2.balanceOf(manager);
        bidder1.doBid(manager, 1, 11 * T2);
        bidder2.doBid(manager, 1, 12 * T2);
        var bidder1_t2_balance_after = t2.balanceOf(bidder1);
        var manager_t2_balance_after = t2.balanceOf(manager);

        var bidder_balance_diff = bidder1_t2_balance_before - bidder1_t2_balance_after;
        var manager_balance_diff = manager_t2_balance_after - manager_t2_balance_before;
        assertEq(bidder_balance_diff, 0 * T2);
        assertEq(manager_balance_diff, 12 * T2);
    }
    function testFailBidExpired() {
        manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        bidder1.doBid(manager, 1, 11 * T2);

        // force expiry
        manager.setTime(manager.getTime() + 2 years);

        bidder2.doBid(manager, 1, 12 * T2);
    }
    function testClaimTransfersBenefactor() {
        var seller_t2_balance_before = t2.balanceOf(seller);
        var seller_t1_balance_before = t1.balanceOf(seller);

        var id = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        bidder1.doBid(manager, 1, 40 * T2);
        seller.doClaim(manager, id);

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

        var id = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        bidder1.doBid(manager, 1, 40 * T2);
        bidder2.doBid(manager, 1, 60 * T2);
        seller.doClaim(manager, id);

        var seller_t2_balance_after = t2.balanceOf(seller);
        var seller_t1_balance_after = t1.balanceOf(seller);

        var diff_t1 = seller_t1_balance_before - seller_t1_balance_after;
        var diff_t2 = seller_t2_balance_after - seller_t2_balance_before;

        assertEq(diff_t2, 60 * T2);
        assertEq(diff_t1, 100 * T1);
    }
    function testBenefactorClaimLogged() {
        var id = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        bidder1.doBid(manager, 1, 11 * T2);
        seller.doClaim(manager, id);

        var seller_t1_balance_before = t1.balanceOf(seller);
        var seller_t2_balance_before = t2.balanceOf(seller);

        // calling claim again should not do anything as there
        // have been no new bids
        seller.doClaim(manager, id);

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

        var id = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        bidder1.doBid(manager, 1, 11 * T2);

        // force expiry
        manager.setTime(manager.getTime() + 2 years);

        bidder1.doClaim(manager, 1);

        var bidder_t2_balance_after = t2.balanceOf(bidder1);
        var bidder_t1_balance_after = t1.balanceOf(bidder1);

        var diff_t1 = bidder_t1_balance_after - bidder_t1_balance_before;
        var diff_t2 = bidder_t2_balance_before - bidder_t2_balance_after;

        assertEq(diff_t2, 11 * T2);
        assertEq(diff_t1, 100 * T1);
    }
    function testFailClaimNonParty() {
        var id = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        bidder1.doBid(manager, 1, 11 * T2);
        // bidder2 is not party to the auction and should not be able to
        // initiate a claim
        bidder2.doClaim(manager, 1);
    }
    function testFailClaimProceedingsPreExpiration() {
        // bidders cannot claim their auctionlet until the auction has
        // expired.
        var id = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        bidder1.doBid(manager, 1, 11 * T2);
        bidder1.doClaim(manager, 1);
    }
    function testMultipleNewAuctions() {
        // auction manager should be able to manage multiple auctions
        t2.transfer(seller, 200 * T2);
        seller.doApprove(manager, 200 * T2, t2);

        var t1_balance_before = t1.balanceOf(seller);
        var t2_balance_before = t2.balanceOf(seller);

        var id1 = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        var id2 = manager.newAuction(seller, t2, t1, 100 * T2, 10 * T1, 1 * T1, 1 years);

        var t1_balance_after = t1.balanceOf(seller);
        var t2_balance_after = t2.balanceOf(seller);

        assertEq(id1, 1);
        assertEq(id2, 2);

        var t1_balance_diff = t1_balance_before - t1_balance_after;
        var t2_balance_diff = t2_balance_before - t2_balance_after;

        assertEq(t1_balance_diff, 100 * T1);
        assertEq(t2_balance_diff, 100 * T2);

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

        var id = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        bidder1.doBid(manager, 2, 11 * T2);
        seller.doClaim(manager, id);

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
        var id1 = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 0 years);
        var id2 = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 0 years);

        // create bids on two different auctions so that the manager has
        // enough funds for us to attempt to withdraw all at once
        bidder1.doBid(manager, 1, 11 * T2);
        bidder2.doBid(manager, 2, 11 * T2);

        // now attempt to claim the proceedings from the first
        // auctionlet twice
        bidder1.doClaim(manager, 1);
        bidder1.doClaim(manager, 1);
    }
    function testSplitBase() {
        var id = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);

        var (auction_id0, last_bidder0,
             last_bid0, quantity0) = manager.getAuctionlet(1);

        var (nid, sid) = bidder1.doBid(manager, 1, 7 * T2, 60 * T1);

        var (auction_id1, last_bidder1,
             last_bid1, quantity1) = manager.getAuctionlet(nid);

        var expected_new_bid = 0;
        var expected_new_quantity = 40 * T1;

        assertEq(auction_id0, auction_id1);
        assertEq(last_bidder0, 0x00);
        assertEq(last_bidder1, 0x00);

        assertEq(last_bid0, 0 * T2);
        assertEq(quantity0, 100 * T1);

        assertEq(last_bid1, expected_new_bid);
        assertEq(quantity1, expected_new_quantity);
    }
    function testSplitTransfer() {
        manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);

        var bidder1_t2_balance_before = t2.balanceOf(bidder1);
        bidder1.doBid(manager, 1, 7 * T2, 60 * T1);
        var bidder1_t2_balance_after = t2.balanceOf(bidder1);

        var balance_diff = bidder1_t2_balance_before - bidder1_t2_balance_after;
        assertEq(balance_diff, 7 * T2);
    }
    function testSplitBaseResult() {
        var id1 = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);

        var (nid, sid) = bidder1.doBid(manager, 1, 7 * T2, 60 * T1);

        var (auction_id1, last_bidder1,
             last_bid1, quantity1) = manager.getAuctionlet(nid);
        var (auction_id2, last_bidder2,
             last_bid2, quantity2) = manager.getAuctionlet(sid);

        assertEq(auction_id1, auction_id2);
        assertEq(last_bidder1, 0x00);
        assertEq(last_bidder2, bidder1);

        var expected_new_quantity1 = 40 * T1;
        var expected_new_quantity2 = 60 * T1;

        assertEq(quantity1, expected_new_quantity1);
        assertEq(quantity2, expected_new_quantity2);

        // we expect the bid on the existing auctionlet to remain as
        // zero as it is a base auctionlet
        var expected_new_bid1 = 0;
        var expected_new_bid2 = 7 * T2;

        assertEq(last_bid1, expected_new_bid1);
        assertEq(last_bid2, expected_new_bid2);
    }
    function testSplitAfterBid() {
        var id1 = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);

        bidder1.doBid(manager, 1, 11 * T2);

        // make split bid that has equivalent price of 20 T2 for full lot
        var (nid, sid) = bidder2.doBid(manager, 1, 12 * T2, 60 * T1);

        var (auction_id1, last_bidder1,
             last_bid1, quantity1) = manager.getAuctionlet(nid);
        var (auction_id2, last_bidder2,
             last_bid2, quantity2) = manager.getAuctionlet(sid);

        assertEq(auction_id1, auction_id2);
        assertEq(last_bidder1, bidder1);
        assertEq(last_bidder2, bidder2);

        // Splitting a bid produces two new bids - the 'splitting' bid
        // and a 'modified' bid.
        // The original bid has quantity q0 and bid amount b0.
        // The modified bid has quantity q1 and bid amount b1.
        // The splitting bid has quantity q2 and bid amount b2.
        // The splitting bid must satisfy (b2 / q2) > (b0 / q0)
        // and q2 < q0, i.e. it must be an increase in order valuation,
        // but a decrease in quantity.
        // The modified bid conserves *valuation*: (q1 / b1) = (q0 / b0)
        // and has reduced quantity: q1 = q0 - q2.
        // The unknown modified bid b1 is determined by b1 = b0 (q1 / q0),
        // i.e. the originial bid scaled by the quantity change.

        var expected_new_quantity2 = 60 * T1;
        var expected_new_bid2 = 12 * T2;

        var expected_new_quantity1 = 100 * T1 - expected_new_quantity2;
        var expected_new_bid1 = (11 * T2 * expected_new_quantity1) / (100 * T1);

        assertEq(quantity1, expected_new_quantity1);
        assertEq(quantity2, expected_new_quantity2);

        assertEq(last_bid1, expected_new_bid1);
        assertEq(last_bid2, expected_new_bid2);
    }
    function testFailSplitExcessQuantity() {
        manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        bidder1.doBid(manager, 1, 7 * T2, 101 * T1);
    }
    function testFailSplitLowerValue() {
        // The splitting bid must satisfy (b2 / q2) > (b0 / q0)
        // and q2 < q0, i.e. it must be an increase in order valuation,
        // but a decrease in quantity.
        manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        bidder1.doBid(manager, 1, 11 * T2);

        bidder2.doBid(manager, 1, 5 * T2, 50 * T1);
    }
    function testFailSplitUnderMinBid() {
        // Splitting bids have to be over the scaled minimum bid
        manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        bidder1.doBid(manager, 1, 4 * T2, 50 * T1);
    }
    function testFailSplitUnderMinIncrease() {
        // Splitting bids have to increase more than the scaled minimum
        // increase
        manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 10 * T2, 1 years);
        bidder1.doBid(manager, 1, 10 * T2);

        bidder2.doBid(manager, 1, 6 * T2, 50 * T1);
    }
    function testFailSplitExpired() {
        manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        bidder1.doBid(manager, 1, 11 * T2);

        // force expiry
        manager.setTime(manager.getTime() + 2 years);

        bidder2.doBid(manager, 1, 10 * T2, 50 * T1);
    }
    function testSplitReturnsToPrevBidder() {
        var id = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);

        var bidder1_t2_balance_before = t2.balanceOf(bidder1);
        bidder1.doBid(manager, 1, 20 * T2);
        bidder2.doBid(manager, 1, 20 * T2, 50 * T1);
        var bidder1_t2_balance_after = t2.balanceOf(bidder1);

        var bidder_balance_diff = bidder1_t2_balance_before - bidder1_t2_balance_after;
        assertEq(bidder_balance_diff, 10 * T2);
    }
    function testClaimTransfersBenefactorAfterSplit() {
        var seller_t2_balance_before = t2.balanceOf(seller);
        var seller_t1_balance_before = t1.balanceOf(seller);

        var id = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        bidder1.doBid(manager, 1, 40 * T2);
        bidder2.doBid(manager, 1, 20 * T2, 25 * T1);

        var manager_t2_balance_before_claim = t2.balanceOf(manager);
        assertEq(manager_t2_balance_before_claim, 50 * T2);

        seller.doClaim(manager, id);

        var seller_t2_balance_after = t2.balanceOf(seller);
        var seller_t1_balance_after = t1.balanceOf(seller);

        var diff_t1 = seller_t1_balance_before - seller_t1_balance_after;
        var diff_t2 = seller_t2_balance_after - seller_t2_balance_before;

        assertEq(diff_t2, 50 * T2);
        assertEq(diff_t1, 100 * T1);
    }
    function testFailBidAfterSplit() {
        // splitting deletes the old auctionlet_id
        // bidding on this id should error
        var id1 = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        var (nid, sid) = bidder2.doBid(manager, 1, 12 * T2, 60 * T1);
        bidder1.doBid(manager, 1, 11 * T2);
    }
    function testFailSplitAfterSplit() {
        // splitting deletes the old auctionlet_id
        // splitting on this id should error
        var id1 = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        var (nid, sid) = bidder2.doBid(manager, 1, 12 * T2, 60 * T1);
        bidder1.doBid(manager, 1, 20 * T2, 60 * T1);
    }
}
