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

    ERC20 mkr;
    ERC20 dai;

    function setUp() {
        manager = new Manager();

        mkr = new ERC20Base(1000000);
        dai = new ERC20Base(1000000);

        seller = new AuctionTester();
        seller._target(manager);

        dai.transfer(seller, 200);
        seller.doApprove(manager, 200, dai);

        bidder1 = new AuctionTester();
        bidder1._target(manager);

        mkr.transfer(bidder1, 1000);
        bidder1.doApprove(manager, 1000, mkr);

        bidder2 = new AuctionTester();
        bidder2._target(manager);

        mkr.transfer(bidder2, 1000);
        bidder2.doApprove(manager, 1000, mkr);
    }
    function testSetUp() {
        assertEq(mkr.balanceOf(bidder1), 1000);
        assertEq(mkr.allowance(bidder1, manager), 1000);
    }
    function testNewAuction() {
        var balance_before = dai.balanceOf(seller);
        var id = manager.newAuction(seller,// beneficiary
                                    dai,   // selling
                                    mkr,   // buying
                                    100,   // sell amount (dai)
                                    0,     // minimum bid (mkr)
                                    1);    // minimum increase
        assertEq(id, 1);
        var balance_after = dai.balanceOf(seller);

        var (beneficiary, selling, buying,
             sell_amount, min_bid, min_increase) = manager.getAuction(id);

        assertEq(beneficiary, seller);
        assertTrue(selling == dai);
        assertTrue(buying == mkr);
        assertEq(sell_amount, 100);
        assertEq(min_bid, 0);
        assertEq(min_increase, 1);

        var balance_diff = balance_before - balance_after;
        assertEq(balance_diff, 100);
    }
    function testNewAuctionlet() {
        var id = manager.newAuction(seller, dai, mkr, 100, 0, 1);

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
        var id = manager.newAuction(seller, dai, mkr, 100, 10, 1);
        Manager(bidder1).bid(1, 9);
    }
    function testFailBidOverLast() {
        var id = manager.newAuction(seller, dai, mkr, 100, 0, 1);
        Manager(bidder1).bid(1, 0);
    }
    function testBid() {
        var id = manager.newAuction(seller, dai, mkr, 100, 10, 1);
        Manager(bidder1).bid(1, 11);

        var (auction_id, last_bidder1,
             last_bid, quantity) = manager.getAuctionlet(1);

        assertEq(last_bidder1, bidder1);
        assertEq(last_bid, 11);
    }
    function testFailBidTransfer() {
        var id = manager.newAuction(seller, dai, mkr, 100, 10, 1);

        // this should throw as bidder1 only has 1000 mkr
        Manager(bidder1).bid(1, 1001);
    }
    function testBidTransfer() {
        var id = manager.newAuction(seller, dai, mkr, 100, 10, 1);

        var bidder1_mkr_balance_before = mkr.balanceOf(bidder1);
        Manager(bidder1).bid(1, 11);
        var bidder1_mkr_balance_after = mkr.balanceOf(bidder1);

        var balance_diff = bidder1_mkr_balance_before - bidder1_mkr_balance_after;
        assertEq(balance_diff, 11);
    }
    function testBidReturnsToPrevBidder() {
        var id = manager.newAuction(seller, dai, mkr, 100, 10, 1);

        var bidder1_mkr_balance_before = mkr.balanceOf(bidder1);
        var manager_mkr_balance_before = mkr.balanceOf(manager);
        Manager(bidder1).bid(1, 11);
        Manager(bidder2).bid(1, 12);
        var bidder1_mkr_balance_after = mkr.balanceOf(bidder1);
        var manager_mkr_balance_after = mkr.balanceOf(manager);

        var bidder_balance_diff = bidder1_mkr_balance_before - bidder1_mkr_balance_after;
        var manager_balance_diff = manager_mkr_balance_after - manager_mkr_balance_before;
        assertEq(bidder_balance_diff, 0);
        assertEq(manager_balance_diff, 12);
    }
    function testClaimTransfersBenefactor() {
        var seller_mkr_balance_before = mkr.balanceOf(seller);
        var seller_dai_balance_before = dai.balanceOf(seller);

        var id = manager.newAuction(seller, dai, mkr, 100, 10, 1);
        Manager(bidder1).bid(1, 11);
        manager.claim(id);

        var seller_mkr_balance_after = mkr.balanceOf(seller);
        var seller_dai_balance_after = dai.balanceOf(seller);

        var diff_dai = seller_dai_balance_before - seller_dai_balance_after;
        var diff_mkr = seller_mkr_balance_after - seller_mkr_balance_before;

        assertEq(diff_mkr, 11);
        assertEq(diff_dai, 100);
    }
}
