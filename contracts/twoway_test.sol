import 'dapple/test.sol';
import 'erc20/base.sol';
import 'splitting_auction.sol';

contract Manager is SplittingAuctionManager {
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
    function doBid(uint auctionlet_id, uint bid_how_much, uint sell_amount)
        returns (uint, uint)
    {
        return manager.bid(auctionlet_id, bid_how_much, sell_amount);
    }
    function doClaim(uint id) {
        return manager.claim(id);
    }
}

contract TwoWayTest is Test, EventfulAuction, EventfulManager {
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

        t1.transfer(this, 1000 * T1);
        t2.transfer(this, 1000 * T2);
        t1.approve(manager, 1000 * T1);
        t2.approve(manager, 1000 * T2);
    }
    function newTwoWayAuction() returns (uint, uint) {
        return manager.newTwoWayAuction({beneficiary: seller,
                                         selling: t1,
                                         buying: t2,
                                         sell_amount: 100 * T1,
                                         start_bid: 10 * T2,
                                         min_increase: 1 * T2,
                                         min_decrease: 1 * T1,
                                         duration: 1 years,
                                         COLLECT_MAX: 100 * T2,
                                        });
    }
    function testReversalEvent() {
        var (id, base) = newTwoWayAuction();
        bidder1.doBid(1, 101 * T2);

        expectEventsExact(manager);
        NewAuction(id, base);
        AuctionReversal(id);
        Bid(base);
    }
    function testNewTwoWayAuction() {
        var (id, base) = newTwoWayAuction();
        assertEq(manager.getCollectMax(id), 100 * T2);
    }
    function testBidEqualTargetNoReversal() {
        // bids at or over the target should cause the auction to reverse
        var (id, base) = newTwoWayAuction();
        bidder1.doBid(1, 100 * T2);
        assertEq(manager.isReversed(id), false);
    }
    function testBidOverTargetReversal() {
        // bids at or over the target should cause the auction to reverse
        var (id, base) = newTwoWayAuction();
        bidder1.doBid(1, 101 * T2);
        assertEq(manager.isReversed(id), true);
    }
    function testBidOverTargetRefundsDifference() {
        var (id, base) = newTwoWayAuction();
        var t2_balance_before = t2.balanceOf(bidder1);
        bidder1.doBid(1, 110 * T2);
        var t2_balance_after = t2.balanceOf(bidder1);

        var balance_diff = t2_balance_before - t2_balance_after;
        assertEq(balance_diff, 100 * T2);
    }
    function testBidOverTargetSetsReverseBidder() {
        var (id, base) = newTwoWayAuction();
        bidder1.doBid(1, 110 * T2);

        var (auction_id, last_bidder,
             buy_amount, sell_amount) = manager.getAuctionlet(base);

        assertEq(last_bidder, bidder1);
    }
    function testBidOverTargetSetsReverseBuyAmount() {
        var (id, base) = newTwoWayAuction();
        bidder1.doBid(1, 110 * T2);

        var (auction_id, last_bidder,
             buy_amount, sell_amount) = manager.getAuctionlet(base);

        assertEq(buy_amount, 100 * T2);
    }
    function testBidOverTargetSetsReverseBid() {
        var (id, base) = newTwoWayAuction();
        bidder1.doBid(1, 110 * T2);

        var (auction_id, last_bidder,
             buy_amount, sell_amount) = manager.getAuctionlet(base);

        // as the bidder has bid over the target, we use their surplus
        // valuation to decrease the sell_amount that they will receive.
        //
        // This amount is calculated as q^2 * B / (b * Q), where q is
        // the auctionlet sell_amount, Q is the total auction sell_amount,
        // B is the target and b is the given bid. In an auction with no
        // splitting, q = Q and this simplifies to Q * B / b
        var expected_sell_amount = (100 * T1 * 100 * T2) / (110 * T2);
        assertEq(sell_amount, expected_sell_amount);
    }
    function testBaseSplitEqualTargetNoReversal() {
        var (id, base) = newTwoWayAuction();
        bidder1.doBid(1, 100 * T2, 60 * T1);
        assertEq(manager.isReversed(id), false);
    }
    function testBaseSplitOverTargetReversal() {
        var (id, base) = newTwoWayAuction();
        bidder1.doBid(1, 110 * T2, 60 * T1);
        assertEq(manager.isReversed(id), true);
    }
    function testBaseSplitOverTargetRefundsDifference() {
        var (id, base) = newTwoWayAuction();
        var t2_balance_before = t2.balanceOf(bidder1);
        bidder1.doBid(1, 120 * T2, 60 * T1);
        var t2_balance_after = t2.balanceOf(bidder1);

        var balance_diff = t2_balance_before - t2_balance_after;
        assertEq(balance_diff, 100 * T2);
    }
    function testBaseSplitOverTargetSetsReverseBidder() {
        var (id, base) = newTwoWayAuction();
        var (nid, sid) = bidder1.doBid(1, 120 * T2, 50 * T1);

        var (auction_id, last_bidder,
             buy_amount, sell_amount) = manager.getAuctionlet(sid);

        assertEq(last_bidder, bidder1);
    }
    function testBaseSplitOverTargetSetsReverseBuyAmount() {
        var (id, base) = newTwoWayAuction();
        var (nid, sid) = bidder1.doBid(1, 120 * T2, 50 * T1);

        var (auction_id, last_bidder,
             buy_amount, sell_amount) = manager.getAuctionlet(sid);

        assertEq(buy_amount, 100 * T2);
    }
    function testBaseSplitOverTargetSetsReverseBid() {
        var (id, base) = newTwoWayAuction();
        var (nid, sid) = bidder1.doBid(1, 120 * T2, 50 * T1);

        var (auction_id, last_bidder,
             buy_amount, sell_amount) = manager.getAuctionlet(sid);

        // as the bidder has bid over the target, we use their surplus
        // valuation to decrease the sell_amount that they will receive.
        //
        // This amount is calculated as q^2 * B / (b * Q), where q is
        // the auctionlet sell_amount, Q is the total auction sell_amount,
        // B is the target and b is the given bid.
        var expected_sell_amount = (50 * T1 * 50 * T1 * 100 * T2) / (120 * T2 * 100 * T1);
        assertEq(sell_amount, expected_sell_amount);
    }
}
