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
    function getCollectMax(uint auction_id) returns (uint) {
        return _auctions[auction_id].COLLECT_MAX;
    }
    function isReversed(uint auction_id) returns (bool) {
        return _auctions[auction_id].reversed;
    }
}

contract AuctionTester is Tester {
    Manager manager;
    function bindManager(Manager _manager) {
        _target(_manager);
        manager = Manager(_t);
    }
    function doApprove(address spender, uint value, ERC20 token) {
        token.approve(spender, value);
    }
    function doBid(uint auctionlet_id, uint bid_how_much)
    {
        return manager.bid(auctionlet_id, bid_how_much);
    }
    function doBid(uint auctionlet_id, uint bid_how_much, uint quantity)
        returns (uint, uint)
    {
        return manager.bid(auctionlet_id, bid_how_much, quantity);
    }
    function doClaim(uint id) {
        return manager.claim(id);
    }
}

contract TwoWayTest is Test {
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
    function testNewTwoWayAuction() {
        var id = manager.newTwoWayAuction(seller,  // beneficiary
                                          t1,      // selling
                                          t2,      // buying
                                          100 * T1,// sell amount (t1)
                                          0 * T2,  // minimum bid (t2)
                                          1 * T2,  // minimum increase
                                          1 years, // duration
                                          100 * T2 // COLLECT_MAX
                                         );

        assertEq(manager.getCollectMax(id), 100 * T2);
    }
    function testBidEqualTargetReversal() {
        // bids at or over the target should cause the auction to reverse
        var id = manager.newTwoWayAuction(seller, t1, t2,
                                          100 * T1, 0 * T2, 1 * T2,
                                          1 years, 100 * T2);
        bidder1.doBid(1, 100 * T2);
        assertEq(manager.isReversed(id), true);
    }
    function testBidOverTargetReversal() {
        // bids at or over the target should cause the auction to reverse
        var id = manager.newTwoWayAuction(seller, t1, t2,
                                          100 * T1, 0 * T2, 1 * T2,
                                          1 years, 100 * T2);
        bidder1.doBid(1, 101 * T2);
        assertEq(manager.isReversed(id), true);
    }
    function testBidOverTargetRefundsDifference() {
        var id = manager.newTwoWayAuction(seller, t1, t2,
                                          100 * T1, 0 * T2, 1 * T2,
                                          1 years, 100 * T2);
        var t2_balance_before = t2.balanceOf(bidder1);
        bidder1.doBid(1, 110 * T2);
        var t2_balance_after = t2.balanceOf(bidder1);

        var balance_diff = t2_balance_before - t2_balance_after;
        assertEq(balance_diff, 100 * T2);
    }
    function testBidsDecreasingPostReversal() {
        // after a reversal, bids are strictly decreasing, with a
        // maximum set by the sell amount
        var id = manager.newTwoWayAuction(seller, t1, t2,
                                          100 * T1, 0 * T2, 1 * T2,
                                          1 years, 100 * T2);
        bidder1.doBid(1, 110 * T2);

        var (auction_id1, last_bidder1,
             last_bid1, quantity1) = manager.getAuctionlet(1);

        bidder2.doBid(1, 90 * T1);
        bidder1.doBid(1, 85 * T1);

        var (auction_id2, last_bidder2,
             last_bid2, quantity2) = manager.getAuctionlet(1);

        assertEq(quantity1, 100 * T1);
        assertEq(quantity2, 85 * T1);

        assertEq(last_bid1, 100 * T2);
        assertEq(last_bid2, 100 * T2);
    }
    function testClaimSellerAfterReversal() {
        // after reversal, the seller should receive the available
        // buying token, plus any excess sell token
        var id = manager.newTwoWayAuction(seller, t1, t2,
                                          100 * T1, 0 * T2, 1 * T2,
                                          1 years, 100 * T2);
        bidder1.doBid(1, 100 * T2);
        bidder1.doBid(1, 85 * T1);

        var t1_balance_before = t1.balanceOf(seller);
        var t2_balance_before = t2.balanceOf(seller);

        seller.doClaim(1);

        var t1_balance_after = t1.balanceOf(seller);
        var t2_balance_after = t2.balanceOf(seller);

        var t1_balance_diff = t1_balance_after - t1_balance_before;
        var t2_balance_diff = t2_balance_after - t2_balance_before;

        //@log claim max buying token?
        assertEq(t2_balance_diff, 100 * T2);
        //@log claim excess selling token?
        assertEq(t1_balance_diff, 15 * T1);
    }
    function testClaimBidderAfterReversal() {
        var id = manager.newTwoWayAuction(seller, t1, t2,
                                          100 * T1, 0 * T2, 1 * T2,
                                          1 years, 100 * T2);
        bidder1.doBid(1, 100 * T2);
        bidder1.doBid(1, 85 * T1);

        // force expiry
        manager.setTime(manager.getTime() + 2 years);

        var t1_balance_before = t1.balanceOf(bidder1);
        bidder1.doClaim(1);
        var t1_balance_after = t1.balanceOf(bidder1);
        var t1_balance_diff = t1_balance_after - t1_balance_before;

        assertEq(t1_balance_diff, 85 * T1);
    }
}
