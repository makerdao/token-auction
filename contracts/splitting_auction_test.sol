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
    AuctionTester bidder;

    ERC20 mkr;
    ERC20 dai;

    function setUp() {
        manager = new Manager();

        mkr = new ERC20Base(1000000);
        dai = new ERC20Base(1000000);

        bidder = new AuctionTester();
        bidder._target(manager);

        mkr.transfer(bidder, 1000);
        bidder.doApprove(manager, 1000, mkr);
    }
    function testSetUp() {
        assertEq(mkr.balanceOf(bidder), 1000);
        assertEq(mkr.allowance(bidder, manager), 1000);
    }
    function testNewAuction() {
        var id = manager.newAuction(this,  // beneficiary
                                    dai,   // selling
                                    mkr,   // buying
                                    100,   // sell amount (dai)
                                    0,     // minimum bid (mkr)
                                    1);    // minimum increase
        assertEq(id, 1);

        var (beneficiary, selling, buying,
             sell_amount, min_bid, min_increase) = manager.getAuction(id);

        assertEq(beneficiary, this);
        assertTrue(selling == dai);
        assertTrue(buying == mkr);
        assertEq(sell_amount, 100);
        assertEq(min_bid, 0);
        assertEq(min_increase, 1);
    }
    function testNewAuctionlet() {
        var id = manager.newAuction(this, dai, mkr, 100, 0, 1);

        // can't always know what the auctionlet id is as it is
        // only an internal type. But for the case of a single auction
        // there should be a single auctionlet created with id 1.
        var (auction_id, last_bidder,
             last_bid, quantity) = manager.getAuctionlet(1);

        assertEq(auction_id, id);
        assertEq(last_bidder, 0);
        assertEq(last_bid, 0);
        assertEq(quantity, 100);
    }
    function testFailBidTooLittle() {
        var id = manager.newAuction(this, dai, mkr, 100, 10, 1);
        Manager(bidder).bid(1, 9);
    }
    function testFailBidOverLast() {
        var id = manager.newAuction(this, dai, mkr, 100, 0, 1);
        Manager(bidder).bid(1, 0);
    }
    function testBid() {
        var id = manager.newAuction(this, dai, mkr, 100, 10, 1);
        Manager(bidder).bid(1, 11);

        var (auction_id, last_bidder,
             last_bid, quantity) = manager.getAuctionlet(1);

        assertEq(last_bidder, bidder);
        assertEq(last_bid, 11);
    }
    function testFailBidTransfer() {
        var id = manager.newAuction(this, dai, mkr, 100, 10, 1);

        // this should throw as bidder only has 1000 mkr
        Manager(bidder).bid(1, 1001);
    }
}
