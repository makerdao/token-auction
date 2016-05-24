import 'dapple/test.sol';
import 'erc20/base.sol';
import 'splitting_auction.sol';

contract TestableSplitManager is SplittableAuctionManager {
    uint public debug_timestamp;

    function getTime() public constant returns (uint) {
        return debug_timestamp;
    }
    function setTime(uint timestamp) {
        debug_timestamp = timestamp;
    }
}

contract SplitAuctionTester is Tester {
    TestableSplitManager manager;
    function bindManager(TestableSplitManager _manager) {
        _target(_manager);
        manager = TestableSplitManager(_t);
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

contract SplittingAuctionManagerTest is Test {
    TestableSplitManager manager;
    SplitAuctionTester seller;
    SplitAuctionTester bidder1;
    SplitAuctionTester bidder2;

    ERC20 t1;
    ERC20 t2;

    // use prime numbers to avoid coincidental collisions
    uint constant T1 = 5 ** 12;
    uint constant T2 = 7 ** 10;

    function setUp() {
        manager = new TestableSplitManager();
        manager.setTime(block.timestamp);

        var million = 10 ** 6;

        t1 = new ERC20Base(million * T1);
        t2 = new ERC20Base(million * T2);

        seller = new SplitAuctionTester();
        seller.bindManager(manager);

        t1.transfer(seller, 200 * T1);
        seller.doApprove(manager, 200 * T1, t1);

        bidder1 = new SplitAuctionTester();
        bidder1.bindManager(manager);

        t2.transfer(bidder1, 1000 * T2);
        bidder1.doApprove(manager, 1000 * T2, t2);

        bidder2 = new SplitAuctionTester();
        bidder2.bindManager(manager);

        t2.transfer(bidder2, 1000 * T2);
        bidder2.doApprove(manager, 1000 * T2, t2);
    }
    function testSetUp() {
        assertEq(t2.balanceOf(bidder1), 1000 * T2);
        assertEq(t2.allowance(bidder1, manager), 1000 * T2);
    }
    function testSplitBase() {
        var (base, id) = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);

        var (auction_id0, last_bidder0,
             buy_amount0, sell_amount0) = manager.getAuctionlet(base);

        var (nid, sid) = bidder1.doBid(base, 7 * T2, 60 * T1);

        var (auction_id1, last_bidder1,
             buy_amount1, sell_amount1) = manager.getAuctionlet(nid);

        var expected_new_bid = 0;
        var expected_new_sell_amount = 40 * T1;

        assertEq(auction_id0, auction_id1);
        assertEq(last_bidder0, manager);
        assertEq(last_bidder1, manager);

        assertEq(buy_amount0, 0 * T2);
        assertEq(sell_amount0, 100 * T1);

        assertEq(buy_amount1, expected_new_bid);
        assertEq(sell_amount1, expected_new_sell_amount);
    }
    function testSplitTransfer() {
        var (id, base) = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);

        var bidder1_t2_balance_before = t2.balanceOf(bidder1);
        bidder1.doBid(base, 7 * T2, 60 * T1);
        var bidder1_t2_balance_after = t2.balanceOf(bidder1);

        var balance_diff = bidder1_t2_balance_before - bidder1_t2_balance_after;
        assertEq(balance_diff, 7 * T2);
    }
    function testSplitBaseAddresses() {
        var (id, base) = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);

        var (nid, sid) = bidder1.doBid(base, 7 * T2, 60 * T1);

        var (auction_id1, last_bidder1,
             buy_amount1, sell_amount1) = manager.getAuctionlet(nid);
        var (auction_id2, last_bidder2,
             buy_amount2, sell_amount2) = manager.getAuctionlet(sid);

        assertEq(auction_id1, auction_id2);
        assertEq(last_bidder1, manager);
        assertEq(last_bidder2, bidder1);
    }
    function testSplitBaseResult() {
        var (id, base) = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);

        var (nid, sid) = bidder1.doBid(base, 7 * T2, 60 * T1);

        uint sell_amount1;
        uint sell_amount2;

        uint buy_amount1;
        uint buy_amount2;

        uint _;
        address __;

        (_, __, buy_amount1, sell_amount1) = manager.getAuctionlet(nid);
        (_, __, buy_amount2, sell_amount2) = manager.getAuctionlet(sid);

        var expected_new_sell_amount1 = 40 * T1;
        var expected_new_sell_amount2 = 60 * T1;

        assertEq(sell_amount1, expected_new_sell_amount1);
        assertEq(sell_amount2, expected_new_sell_amount2);

        // we expect the bid on the existing auctionlet to remain as
        // zero as it is a base auctionlet
        var expected_new_bid1 = 0;
        var expected_new_bid2 = 7 * T2;

        assertEq(buy_amount1, expected_new_bid1);
        assertEq(buy_amount2, expected_new_bid2);
    }
    function testSplitAfterBidAddresses() {
        var (id, base) = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);

        bidder1.doBid(base, 11 * T2);

        // make split bid that has equivalent price of 20 T2 for full lot
        var (nid, sid) = bidder2.doBid(base, 12 * T2, 60 * T1);

        var (auction_id1, last_bidder1,
             buy_amount1, sell_amount1) = manager.getAuctionlet(nid);
        var (auction_id2, last_bidder2,
             buy_amount2, sell_amount2) = manager.getAuctionlet(sid);

        assertEq(auction_id1, auction_id2);
        assertEq(last_bidder1, bidder1);
        assertEq(last_bidder2, bidder2);
    }
    function testSplitAfterBidQuantities() {
        var (id, base) = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);

        bidder1.doBid(base, 11 * T2);

        // make split bid that has equivalent price of 20 T2 for full lot
        var (nid, sid) = bidder2.doBid(base, 12 * T2, 60 * T1);

        uint sell_amount1;
        uint sell_amount2;

        uint buy_amount1;
        uint buy_amount2;

        uint _;
        address __;

        (_, __, buy_amount1, sell_amount1) = manager.getAuctionlet(nid);
        (_, __, buy_amount2, sell_amount2) = manager.getAuctionlet(sid);

        // Splitting a bid produces two new bids - the 'splitting' bid
        // and a 'modified' bid.
        // The original bid has sell_amount q0 and bid amount b0.
        // The modified bid has sell_amount q1 and bid amount b1.
        // The splitting bid has sell_amount q2 and bid amount b2.
        // The splitting bid must satisfy (b2 / q2) > (b0 / q0)
        // and q2 < q0, i.e. it must be an increase in order valuation,
        // but a decrease in sell_amount.
        // The modified bid conserves *valuation*: (q1 / b1) = (q0 / b0)
        // and has reduced sell_amount: q1 = q0 - q2.
        // The unknown modified bid b1 is determined by b1 = b0 (q1 / q0),
        // i.e. the originial bid scaled by the sell_amount change.

        var expected_new_sell_amount2 = 60 * T1;
        var expected_new_bid2 = 12 * T2;

        var expected_new_sell_amount1 = 100 * T1 - expected_new_sell_amount2;
        var expected_new_bid1 = (11 * T2 * expected_new_sell_amount1) / (100 * T1);

        assertEq(sell_amount1, expected_new_sell_amount1);
        assertEq(sell_amount2, expected_new_sell_amount2);

        assertEq(buy_amount1, expected_new_bid1);
        assertEq(buy_amount2, expected_new_bid2);
    }
    function testFailSplitExcessQuantity() {
        var (id, base) = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        bidder1.doBid(base, 7 * T2, 101 * T1);
    }
    function testPassSplitLowerValue() {
        // The splitting bid must satisfy (b2 / q2) > (b0 / q0)
        // and q2 < q0, i.e. it must be an increase in order valuation,
        // but a decrease in sell_amount.
        var (id, base) = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        bidder1.doBid(base, 6 * T2, 50 * T1);
    }
    function testFailSplitLowerValue() {
        // The splitting bid must satisfy (b2 / q2) > (b0 / q0)
        // and q2 < q0, i.e. it must be an increase in order valuation,
        // but a decrease in sell_amount.
        var (id, base) = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        bidder1.doBid(base, 11 * T2);

        bidder2.doBid(base, 5 * T2, 50 * T1);
    }
    function testFailSplitUnderMinBid() {
        // Splitting bids have to be over the scaled minimum bid
        var (id, base) = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        bidder1.doBid(base, 4 * T2, 50 * T1);
    }
    function testFailSplitUnderMinIncrease() {
        // Splitting bids have to increase more than the scaled minimum
        // increase
        var (id, base) = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 10 * T2, 1 years);
        bidder1.doBid(base, 10 * T2);

        bidder2.doBid(base, 6 * T2, 50 * T1);
    }
    function testFailSplitExpired() {
        var (id, base) = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        bidder1.doBid(base, 11 * T2);

        // force expiry
        manager.setTime(manager.getTime() + 2 years);

        bidder2.doBid(base, 10 * T2, 50 * T1);
    }
    function testSplitReturnsToPrevBidder() {
        var (base, id) = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);

        var bidder1_t2_balance_before = t2.balanceOf(bidder1);
        bidder1.doBid(base, 20 * T2);
        bidder2.doBid(base, 20 * T2, 50 * T1);
        var bidder1_t2_balance_after = t2.balanceOf(bidder1);

        var bidder_balance_diff = bidder1_t2_balance_before - bidder1_t2_balance_after;
        assertEq(bidder_balance_diff, 10 * T2);
    }
    function testClaimTransfersBenefactorAfterSplit() {
        var seller_t2_balance_before = t2.balanceOf(seller);
        var seller_t1_balance_before = t1.balanceOf(seller);

        var (base, id) = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        bidder1.doBid(base, 40 * T2);
        bidder2.doBid(base, 20 * T2, 25 * T1);

        var manager_t2_balance_before_claim = t2.balanceOf(manager);
        assertEq(manager_t2_balance_before_claim, 50 * T2);

        seller.doClaim(id);

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
        var (id, base) = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        var (nid, sid) = bidder2.doBid(base, 12 * T2, 60 * T1);
        bidder1.doBid(base, 11 * T2);
    }
    function testFailSplitAfterSplit() {
        // splitting deletes the old auctionlet_id
        // splitting on this id should error
        var (id, base) = manager.newAuction(seller, t1, t2, 100 * T1, 10 * T2, 1 * T2, 1 years);
        var (nid, sid) = bidder2.doBid(base, 12 * T2, 60 * T1);
        bidder1.doBid(base, 20 * T2, 60 * T1);
    }
}
