import 'dapple/test.sol';
import 'erc20/base.sol';
import 'splitting_auction.sol';

contract AuctionTester is Tester {
    function doApprove(address spender, uint value, ERC20 token) {
        token.approve(spender, value);
    }

}

// shorthand
contract Manager is SplittableAuctionManager {}

contract SplittingAuctionManagerTest is Test {
    Manager manager;
    AuctionTester seller;
    AuctionTester bidder1;
    AuctionTester bidder2;

    ERC20 t1;
    ERC20 t2;

    uint BASE = 10 ** 18;

    function setUp() {
        manager = new Manager();

        var million = 10 ** 6 * BASE;

        t1 = new ERC20Base(million);
        t2 = new ERC20Base(million);

        seller = new AuctionTester();
        seller._target(manager);

        t1.transfer(seller, 200);
        seller.doApprove(manager, 200, t1);

        bidder1 = new AuctionTester();
        bidder1._target(manager);

        t2.transfer(bidder1, 1000);
        bidder1.doApprove(manager, 1000, t2);

        bidder2 = new AuctionTester();
        bidder2._target(manager);

        t2.transfer(bidder2, 1000);
        bidder2.doApprove(manager, 1000, t2);
    }
    function testSetUp() {
        assertEq(t2.balanceOf(bidder1), 1000);
        assertEq(t2.allowance(bidder1, manager), 1000);
    }
    function testNewAuction() {
        var balance_before = t1.balanceOf(seller);
        var id = manager.newAuction(seller,  // beneficiary
                                    t1,      // selling
                                    t2,      // buying
                                    100,     // sell amount (t1)
                                    0,       // minimum bid (t2)
                                    1,       // minimum increase
                                    1 years  // duration
                                   );
        assertEq(id, 1);
        var balance_after = t1.balanceOf(seller);

        var (beneficiary, selling, buying,
             sell_amount, min_bid, min_increase, expiration) = manager.getAuction(id);

        assertEq(beneficiary, seller);
        assertTrue(selling == t1);
        assertTrue(buying == t2);
        assertEq(sell_amount, 100);
        assertEq(min_bid, 0);
        assertEq(min_increase, 1);
        assertEq(expiration, block.timestamp + 1 years);

        var balance_diff = balance_before - balance_after;
        assertEq(balance_diff, 100);
    }
    function testNewAuctionlet() {
        var id = manager.newAuction(seller, t1, t2, 100, 0, 1, 1 years);

        // can't always know what the auctionlet id is as it is
        // only an internal type. But for the case of a single auction
        // there should be a single auctionlet created with id 1.
        var (auction_id, last_bidder1,
             last_bid, quantity) = manager.getAuctionlet(1);

        assertEq(auction_id, id);
        assertEq(last_bidder1, 0);
        assertEq(last_bid, 0);
        assertEq(quantity, 100);
    }
    function testFailBidTooLittle() {
        var id = manager.newAuction(seller, t1, t2, 100, 10, 1, 1 years);
        Manager(bidder1).bid(1, 9);
    }
    function testFailBidOverLast() {
        var id = manager.newAuction(seller, t1, t2, 100, 0, 1, 1 years);
        Manager(bidder1).bid(1, 0);
    }
    function testBid() {
        var id = manager.newAuction(seller, t1, t2, 100, 10, 1, 1 years);
        Manager(bidder1).bid(1, 11);

        var (auction_id, last_bidder1,
             last_bid, quantity) = manager.getAuctionlet(1);

        assertEq(last_bidder1, bidder1);
        assertEq(last_bid, 11);
    }
    function testFailBidTransfer() {
        var id = manager.newAuction(seller, t1, t2, 100, 10, 1, 1 years);

        // this should throw as bidder1 only has 1000 t2
        Manager(bidder1).bid(1, 1001);
    }
    function testBidTransfer() {
        var id = manager.newAuction(seller, t1, t2, 100, 10, 1, 1 years);

        var bidder1_t2_balance_before = t2.balanceOf(bidder1);
        Manager(bidder1).bid(1, 11);
        var bidder1_t2_balance_after = t2.balanceOf(bidder1);

        var balance_diff = bidder1_t2_balance_before - bidder1_t2_balance_after;
        assertEq(balance_diff, 11);
    }
    function testBidReturnsToPrevBidder() {
        var id = manager.newAuction(seller, t1, t2, 100, 10, 1, 1 years);

        var bidder1_t2_balance_before = t2.balanceOf(bidder1);
        var manager_t2_balance_before = t2.balanceOf(manager);
        Manager(bidder1).bid(1, 11);
        Manager(bidder2).bid(1, 12);
        var bidder1_t2_balance_after = t2.balanceOf(bidder1);
        var manager_t2_balance_after = t2.balanceOf(manager);

        var bidder_balance_diff = bidder1_t2_balance_before - bidder1_t2_balance_after;
        var manager_balance_diff = manager_t2_balance_after - manager_t2_balance_before;
        assertEq(bidder_balance_diff, 0);
        assertEq(manager_balance_diff, 12);
    }
    function testClaimTransfersBenefactor() {
        var seller_t2_balance_before = t2.balanceOf(seller);
        var seller_t1_balance_before = t1.balanceOf(seller);

        var id = manager.newAuction(seller, t1, t2, 100, 10, 1, 1 years);
        Manager(bidder1).bid(1, 11);
        Manager(seller).claim(id);

        var seller_t2_balance_after = t2.balanceOf(seller);
        var seller_t1_balance_after = t1.balanceOf(seller);

        var diff_t1 = seller_t1_balance_before - seller_t1_balance_after;
        var diff_t2 = seller_t2_balance_after - seller_t2_balance_before;

        assertEq(diff_t2, 11);
        assertEq(diff_t1, 100);
    }
    function testBenefactorClaimLogged() {
        var id = manager.newAuction(seller, t1, t2, 100, 10, 1, 1 years);
        Manager(bidder1).bid(1, 11);
        Manager(seller).claim(id);

        var seller_t2_balance_before = t2.balanceOf(seller);
        var seller_t1_balance_before = t1.balanceOf(seller);

        // calling claim again should not do anything as there
        // have been no new bids
        Manager(seller).claim(id);

        var seller_t2_balance_after = t2.balanceOf(seller);
        var seller_t1_balance_after = t1.balanceOf(seller);

        var diff_t1 = seller_t1_balance_before - seller_t1_balance_after;
        var diff_t2 = seller_t2_balance_after - seller_t2_balance_before;

        assertEq(diff_t2, 0);
        assertEq(diff_t1, 0);
    }
    function testClaimTransfersBidder() {
        var bidder_t2_balance_before = t2.balanceOf(bidder1);
        var bidder_t1_balance_before = t1.balanceOf(bidder1);

        // create an auction that expires immediately
        var id = manager.newAuction(seller, t1, t2, 100, 10, 1, 0);
        Manager(bidder1).bid(1, 11);
        Manager(bidder1).claim(1);

        var bidder_t2_balance_after = t2.balanceOf(bidder1);
        var bidder_t1_balance_after = t1.balanceOf(bidder1);

        var diff_t1 = bidder_t1_balance_after - bidder_t1_balance_before;
        var diff_t2 = bidder_t2_balance_before - bidder_t2_balance_after;

        assertEq(diff_t2, 11);
        assertEq(diff_t1, 100);
    }
    function testFailClaimNonParty() {
        var id = manager.newAuction(seller, t1, t2, 100, 10, 1, 1 years);
        Manager(bidder1).bid(1, 11);
        // bidder2 is not party to the auction and should not be able to
        // initiate a claim
        Manager(bidder2).claim(1);
    }
    function testFailClaimProceedingsPreExpiration() {
        // bidders cannot claim their auctionlet until the auction has
        // expired.
        var id = manager.newAuction(seller, t1, t2, 100, 10, 1, 1 years);
        Manager(bidder1).bid(1, 11);
        Manager(bidder1).claim(1);
    }
}
