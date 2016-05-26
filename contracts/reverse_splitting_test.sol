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
    function doBid(uint auctionlet_id, uint bid_how_much, uint sell_amount)
        returns (uint, uint)
    {
        return manager.bid(auctionlet_id, bid_how_much, sell_amount);
    }
    function doClaim(uint id) {
        return manager.claim(id);
    }
}

contract ReverseSplittingTest is Test {
    Manager manager;
    AuctionTester seller;
    AuctionTester bidder1;
    AuctionTester bidder2;

    ERC20 t1;
    ERC20 t2;

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
    function newReverseAuction() returns (uint, uint) {
        return manager.newReverseAuction({beneficiary: seller,
                                          selling: t1,
                                          buying: t2,
                                          max_sell_amount: 100 * T1,
                                          buy_amount: 5 * T2,
                                          min_decrease: 2 * T1,
                                          duration: 1 years
                                        });
    }
    function testNewReverseAuction() {
        var (id, base) = newReverseAuction();

        assertEq(manager.getCollectMax(id), 0);
        assertEq(manager.isReversed(id), true);

        var (auction_id, last_bidder,
             buy_amount, sell_amount) = manager.getAuctionlet(base);

        assertEq(auction_id, 1);
        assertEq(last_bidder, seller);
        assertEq(buy_amount, 5 * T2);
        assertEq(sell_amount, 100 * T1);
    }
    function testSplitBase() {
        var (id, base) = newReverseAuction();

        var (auction_id0, last_bidder0,
             last_bid0, quantity0) = manager.getAuctionlet(base);

        var (nid, sid) = bidder1.doBid(base, 40 * T1, 4 * T2);

        var (auction_id1, last_bidder1,
             last_bid1, quantity1) = manager.getAuctionlet(nid);

        var expected_new_buy_amount = 1 * T2;
        var expected_new_sell_amount = 20 * T1;

        assertEq(auction_id0, auction_id1);
        assertEq(last_bidder0, seller);
        assertEq(last_bidder1, seller);

        assertEq(last_bid0, 5 * T2);
        assertEq(quantity0, 100 * T1);

        assertEq(last_bid1, expected_new_buy_amount);
        assertEq(quantity1, expected_new_sell_amount);
    }
    function testSplitTransfersFromBidder() {
        var (id, base) = newReverseAuction();

        var bidder1_t2_balance_before = t2.balanceOf(bidder1);
        bidder1.doBid(base, 40 * T1, 4 * T2);
        var bidder1_t2_balance_after = t2.balanceOf(bidder1);

        var balance_diff = bidder1_t2_balance_before - bidder1_t2_balance_after;
        assertEq(balance_diff, 4 * T2);
    }
    function testSplitBaseAddresses() {
        var (id, base) = newReverseAuction();

        var (nid, sid) = bidder1.doBid(base, 40 * T1, 4 * T2);

        var (auction_id1, last_bidder1,
             buy_amount1, sell_amount1) = manager.getAuctionlet(nid);
        var (auction_id2, last_bidder2,
             buy_amount2, sell_amount2) = manager.getAuctionlet(sid);

        assertEq(auction_id1, auction_id2);
        assertEq(last_bidder1, seller);
        assertEq(last_bidder2, bidder1);
    }
    function testSplitBaseResult() {
        var (id, base) = newReverseAuction();

        var (nid, sid) = bidder1.doBid(base, 40 * T1, 4 * T2);

        uint sell_amount1;
        uint sell_amount2;

        uint buy_amount1;
        uint buy_amount2;

        uint _;
        address __;

        (_, __, buy_amount1, sell_amount1) = manager.getAuctionlet(nid);
        (_, __, buy_amount2, sell_amount2) = manager.getAuctionlet(sid);

        var expected_new_sell_amount1 = 20 * T1;
        var expected_new_sell_amount2 = 40 * T1;

        assertEq(sell_amount1, expected_new_sell_amount1);
        assertEq(sell_amount2, expected_new_sell_amount2);

        // we expect the bid on the existing auctionlet to remain at the
        // start bid scaled down proportionally as it is a base auctionlet
        var expected_new_buy_amount1 = 1 * T2;
        var expected_new_buy_amount2 = 4 * T2;

        assertEq(buy_amount1, expected_new_buy_amount1);
        assertEq(buy_amount2, expected_new_buy_amount2);
    }
    function testSplitAfterBidAddresses() {
        var (id, base) = newReverseAuction();
        bidder1.doBid(base, 90 * T1);
        var (nid, sid) = bidder2.doBid(base, 40 * T1, 4 * T2);

        var (auction_id1, last_bidder1,
             buy_amount1, sell_amount1) = manager.getAuctionlet(nid);
        var (auction_id2, last_bidder2,
             buy_amount2, sell_amount2) = manager.getAuctionlet(sid);

        assertEq(auction_id1, auction_id2);
        assertEq(last_bidder1, bidder1);
        assertEq(last_bidder2, bidder2);
    }
    function testSplitAfterBidQuantities() {
        var (id, base) = newReverseAuction();
        bidder1.doBid(base, 90 * T1);
        var (nid, sid) = bidder2.doBid(base, 40 * T1, 4 * T2);

        uint sell_amount1;
        uint sell_amount2;

        uint buy_amount1;
        uint buy_amount2;

        uint _;
        address __;

        (_, __, buy_amount1, sell_amount1) = manager.getAuctionlet(nid);
        (_, __, buy_amount2, sell_amount2) = manager.getAuctionlet(sid);

        var expected_new_buy_amount2 = 4 * T2;
        var expected_new_sell_amount2 = 40 * T1;

        var expected_new_buy_amount1 = 5 * T2 - expected_new_buy_amount2;
        var expected_new_sell_amount1 = (90 * T1 * expected_new_buy_amount1) / (5 * T2);

        assertEq(sell_amount1, expected_new_sell_amount1);
        assertEq(sell_amount2, expected_new_sell_amount2);

        assertEq(buy_amount1, expected_new_buy_amount1);
        assertEq(buy_amount2, expected_new_buy_amount2);
    }
    function testFailSplitExcessQuantity() {
        var (id, base) = newReverseAuction();
        bidder1.doBid(base, 90 * T2, 6 * T1);
    }
    function testPassSplitLowerValue() {
        var (id, base) = newReverseAuction();
        bidder1.doBid(base, 50 * T1, 3 * T2);
    }
    function testFailSplitLowerValue() {
        var (id, base) = newReverseAuction();
        bidder1.doBid(base, 80 * T1);
        bidder2.doBid(base, 40 * T1, 2 * T2);
    }
    function testFailSplitUnderMinBid() {
        var (id, base) = newReverseAuction();
        bidder2.doBid(base, 50 * T1, 2 * T2);
    }
    function testFailSplitUnderMinDecrease() {
        var (id, base) = newReverseAuction();
        bidder1.doBid(base, 90 * T1);
        bidder2.doBid(base, 89 * T1, 3 * T2);
    }
    function testFailSplitExpired() {
        var (id, base) = newReverseAuction();
        bidder1.doBid(base, 90 * T1);

        // force expiry
        manager.setTime(manager.getTime() + 2 years);

        bidder2.doBid(base, 40 * T1, 4 * T2);
    }
    function testSplitReturnsToPrevBidder() {
        var (id, base) = newReverseAuction();

        var bidder1_t2_balance_before = t2.balanceOf(bidder1);
        bidder1.doBid(base, 90 * T1);
        bidder2.doBid(base, 50 * T1, 3 * T2);
        var bidder1_t2_balance_after = t2.balanceOf(bidder1);

        var bidder_balance_diff = bidder1_t2_balance_before - bidder1_t2_balance_after;
        assertEq(bidder_balance_diff, 2 * T2);
    }
    function testTransferToBenefactorAfterSplit() {
        var seller_t2_balance_before = t2.balanceOf(seller);
        var seller_t1_balance_before = t1.balanceOf(seller);

        var (id, base) = newReverseAuction();

        bidder1.doBid(base, 80 * T1);
        bidder2.doBid(base, 40 * T1, 4 * T2);

        var seller_t2_balance_after = t2.balanceOf(seller);
        var seller_t1_balance_after = t1.balanceOf(seller);

        var diff_t1 = seller_t1_balance_before - seller_t1_balance_after;
        var diff_t2 = seller_t2_balance_after - seller_t2_balance_before;

        //@log seller t2 balance change
        assertEq(diff_t2, 5 * T2);
        //@log seller t1 balance change
        // 40 + 80 * (1 / 5) = 56
        assertEq(diff_t1, 56 * T1);
    }
}
