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

    // use prime numbers to avoid coincidental collisions
    uint constant T1 = 5 ** 12;
    uint constant T2 = 7 ** 10;

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
    function newTwoWayAuction() returns (uint, uint) {
        return manager.newTwoWayAuction({beneficiary: seller,
                                         selling: t1,
                                         buying: t2,
                                         sell_amount: 100 * T1,
                                         min_bid: 0 * T2,
                                         min_increase: 1 * T2,
                                         min_decrease: 1 * T1,
                                         duration: 1 years,
                                         COLLECT_MAX: 100 * T2,
                                        });
    }
    function testNewTwoWayAuction() {
        var (base, id) = newTwoWayAuction();
        assertEq(manager.getCollectMax(id), 100 * T2);
    }
    function testBidEqualTargetReversal() {
        // bids at or over the target should cause the auction to reverse
        var (base, id) = newTwoWayAuction();
        bidder1.doBid(1, 100 * T2);
        assertEq(manager.isReversed(id), true);
    }
    function testBidOverTargetReversal() {
        // bids at or over the target should cause the auction to reverse
        var (base, id) = newTwoWayAuction();
        bidder1.doBid(1, 101 * T2);
        assertEq(manager.isReversed(id), true);
    }
    function testBidOverTargetRefundsDifference() {
        var (base, id) = newTwoWayAuction();
        var t2_balance_before = t2.balanceOf(bidder1);
        bidder1.doBid(1, 110 * T2);
        var t2_balance_after = t2.balanceOf(bidder1);

        var balance_diff = t2_balance_before - t2_balance_after;
        assertEq(balance_diff, 100 * T2);
    }
    function testBidOverTargetSetsReverseBid() {
        var (base, id) = newTwoWayAuction();
        bidder1.doBid(1, 110 * T2);

        var (auction_id, last_bidder,
             last_bid, quantity) = manager.getAuctionlet(base);

        assertEq(last_bidder, bidder1);
        assertEq(last_bid, 100 * T2);

        // as the bidder has bid over the target, we use their surplus
        // valuation to decrease the quantity that they will receive.
        //
        // This amount is calculated as q^2 * B / (b * Q), where q is
        // the auctionlet quantity, Q is the total auction quantity,
        // B is the target and b is the given bid. In an auction with no
        // splitting, q = Q and this simplifies to Q * B / b
        var expected_quantity = (100 * T1 * 100 * T2) / (110 * T2);
        assertEq(quantity, expected_quantity);
    }
    function testBidsDecreasingPostReversal() {
        // after a reversal, bids are strictly decreasing, with a
        // maximum set by the sell amount
        var (base, id) = newTwoWayAuction();
        bidder1.doBid(1, 100 * T2);  // force reversal

        bidder2.doBid(1, 90 * T1);

        var (auction_id1, last_bidder1,
             last_bid1, quantity1) = manager.getAuctionlet(base);

        bidder1.doBid(1, 85 * T1);

        var (auction_id2, last_bidder2,
             last_bid2, quantity2) = manager.getAuctionlet(base);

        assertEq(quantity1, 90 * T1);
        assertEq(quantity2, 85 * T1);

        assertEq(last_bid1, 100 * T2);
        assertEq(last_bid2, 100 * T2);
    }
    function testClaimSellerAfterReversal() {
        // after reversal, the seller should receive the available
        // buying token, plus any excess sell token
        var (base, id) = newTwoWayAuction();
        bidder1.doBid(1, 100 * T2);  // force reversal
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
        var (base, id) = newTwoWayAuction();
        bidder1.doBid(1, 100 * T2);  // force the reversal
        bidder1.doBid(1, 85 * T1);

        // force expiry
        manager.setTime(manager.getTime() + 2 years);

        var t1_balance_before = t1.balanceOf(bidder1);
        bidder1.doClaim(1);
        var t1_balance_after = t1.balanceOf(bidder1);
        var t1_balance_diff = t1_balance_after - t1_balance_before;

        assertEq(t1_balance_diff, 85 * T1);
    }
    function testSplitAfterReversal() {
        var (base, id) = newTwoWayAuction();

        bidder1.doBid(1, 100 * T2);  // force the reversal

        bidder1.doBid(1, 90 * T1);

        var (nid, sid) = bidder2.doBid(1, 40 * T1, 50 * T2);
        // this should succeed and create two new auctionlets

        var (auction_id1, last_bidder1,
             last_bid1, quantity1) = manager.getAuctionlet(nid);

        var (auction_id2, last_bidder2,
             last_bid2, quantity2) = manager.getAuctionlet(sid);

        assertEq(auction_id1, auction_id2);

        assertEq(last_bidder1, bidder1);
        assertEq(last_bidder2, bidder2);

        assertEq(last_bid1, 50 * T2);
        assertEq(last_bid2, 50 * T2);

        assertEq(quantity1, 45 * T1);
        assertEq(quantity2, 40 * T1);

        // a split bid can be made in a reverse market.
        // bidders can offer to buy less of the token for a lesser price
        // *provided that they increase the valuation*
    }
}
