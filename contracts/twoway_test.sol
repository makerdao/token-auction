import 'dapple/test.sol';
import 'test_base.sol';
import 'erc20/base.sol';
import 'splitting_auction.sol';

contract TwoWayTest is Test, EventfulAuction, EventfulManager {
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

        t1.transfer(this, 1000 * T1);
        t2.transfer(this, 1000 * T2);
        t1.approve(manager, 1000 * T1);
        t2.approve(manager, 1000 * T2);
    }
    function newTwoWayAuction() returns (uint, uint) {
        return manager.newTwoWayAuction( seller    // beneficiary
                                       , t1        // selling
                                       , t2        // buying
                                       , 100 * T1  // sell_amount
                                       , 10 * T2   // start_bid
                                       , 1 * T2    // min_increase
                                       , 1 * T1    // min_decrease
                                       , 1 years   // duration
                                       , 100 * T2  // collection_limit
                                       );
    }
    function testReversalEvent() {
        var (id, base) = newTwoWayAuction();
        bidder1.doBid(base, 101 * T2);

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
        // bids at the target should not cause the auction to reverse
        var (id, base) = newTwoWayAuction();
        bidder1.doBid(base, 100 * T2);
        assertEq(manager.isReversed(id), false);
    }
    function testBidOverTargetReversal() {
        // bids over the target should cause the auction to reverse
        var (id, base) = newTwoWayAuction();
        bidder1.doBid(base, 101 * T2);
        assertEq(manager.isReversed(id), true);
    }
    function testBidOverTargetRefundsDifference() {
        var (id, base) = newTwoWayAuction();
        var t2_balance_before = t2.balanceOf(bidder1);
        bidder1.doBid(base, 110 * T2);
        var t2_balance_after = t2.balanceOf(bidder1);

        var balance_diff = t2_balance_before - t2_balance_after;
        assertEq(balance_diff, 100 * T2);
    }
    function testBidOverTargetSetsReverseBidder() {
        var (id, base) = newTwoWayAuction();
        bidder1.doBid(base, 110 * T2);

        var (auction_id, last_bidder,
             buy_amount, sell_amount) = manager.getAuctionlet(base);

        assertEq(last_bidder, bidder1);
    }
    function testBidOverTargetSetsReverseBuyAmount() {
        var (id, base) = newTwoWayAuction();
        bidder1.doBid(base, 110 * T2);

        var (auction_id, last_bidder,
             buy_amount, sell_amount) = manager.getAuctionlet(base);

        assertEq(buy_amount, 100 * T2);
    }
    function testBidOverTargetSetsReverseBid() {
        var (id, base) = newTwoWayAuction();
        bidder1.doBid(base, 110 * T2);

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
        bidder1.doBid(base, 100 * T2, 60 * T1);
        assertEq(manager.isReversed(id), false);
    }
    function testBaseSplitOverTargetReversal() {
        var (id, base) = newTwoWayAuction();
        bidder1.doBid(base, 110 * T2, 60 * T1);
        assertEq(manager.isReversed(id), true);
    }
    function testBaseSplitOverTargetRefundsDifference() {
        var (id, base) = newTwoWayAuction();
        var t2_balance_before = t2.balanceOf(bidder1);
        bidder1.doBid(base, 120 * T2, 60 * T1);
        var t2_balance_after = t2.balanceOf(bidder1);

        var balance_diff = t2_balance_before - t2_balance_after;
        assertEq(balance_diff, 100 * T2);
    }
    function testBaseSplitOverTargetSetsReverseBidder() {
        var (id, base) = newTwoWayAuction();
        var (nid, sid) = bidder1.doBid(base, 120 * T2, 50 * T1);

        var (auction_id, last_bidder,
             buy_amount, sell_amount) = manager.getAuctionlet(sid);

        assertEq(last_bidder, bidder1);
    }
    function testBaseSplitOverTargetSetsReverseBuyAmount() {
        var (id, base) = newTwoWayAuction();
        var (nid, sid) = bidder1.doBid(base, 120 * T2, 50 * T1);

        var (auction_id, last_bidder,
             buy_amount, sell_amount) = manager.getAuctionlet(sid);

        assertEq(buy_amount, 100 * T2);
    }
    function testBaseSplitOverTargetSetsReverseBid() {
        var (id, base) = newTwoWayAuction();
        var (nid, sid) = bidder1.doBid(base, 120 * T2, 50 * T1);

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

contract TwoWayMultipleBeneficiariesTest is Test, EventfulAuction, EventfulManager {
    TestableManager manager;
    AuctionTester seller;
    AuctionTester bidder1;
    AuctionTester bidder2;
    AuctionTester beneficiary1;
    AuctionTester beneficiary2;

    ERC20 t1;
    ERC20 t2;

    // use prime numbers to avoid coincidental collisions
    uint constant T1 = 5 ** 12;
    uint constant T2 = 7 ** 10;
    uint constant INFINITY = uint(-1);

    function setUp() {
        manager = new TestableManager();
        manager.setTime(block.timestamp);

        var million = 10 ** 6;

        t1 = new ERC20Base(million * T1);
        t2 = new ERC20Base(million * T2);

        beneficiary1 = new AuctionTester();

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
    function testNewAuction() {
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary1;

        uint[] memory payouts = new uint[](1);
        payouts[0] = 100 * T2;

        var (id1, base1) = manager.newTwoWayAuction( beneficiary1
                                                   , t1
                                                   , t2
                                                   , 100 * T1
                                                   , 10 * T2
                                                   , 1 * T2
                                                   , 1 * T1
                                                   , 1 years
                                                   , 100 * T2
                                                   );
        var (id2, base2) = manager.newTwoWayAuction( beneficiaries
                                                   , payouts
                                                   , t1
                                                   , t2
                                                   , 100 * T1
                                                   , 10 * T2
                                                   , 1 * T2
                                                   , 1 * T1
                                                   , 1 years
                                                   );

        var (beneficiary, selling, buying,
             sell_amount, start_bid, min_increase, expiration) = manager.getAuction(id1);

        assertEq(beneficiary, beneficiary1);

        (beneficiary, selling, buying,
         sell_amount, start_bid, min_increase, expiration) = manager.getAuction(id2);

        assertEq(beneficiary, beneficiary1);
    }
    function newTwoWayTwoPayeeAuction() returns (uint, uint) {
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;

        uint[] memory payouts = new uint[](2);
        payouts[0] = 60 * T2;
        payouts[1] = 40 * T2;

        return manager.newTwoWayAuction( beneficiaries
                                       , payouts
                                       , t1
                                       , t2
                                       , 100 * T1
                                       , 10 * T2
                                       , 1 * T2
                                       , 1 * T1
                                       , 1 years
                                       );
    }
    function testSumPayoutsSetsCollectionLimit() {
        var (id, base) = newTwoWayTwoPayeeAuction();
        bidder1.doBid(base, 101 * T2);

        expectEventsExact(manager);
        NewAuction(id, base);
        AuctionReversal(id);
        Bid(base);

        assertEq(manager.isReversed(id), true);
    }
    function testBidTransfersPartialToFirstPayee() {
        var (id, base) = newTwoWayTwoPayeeAuction();

        var balance_before = t2.balanceOf(beneficiary1);
        bidder1.doBid(base, 50 * T2);
        var balance_after = t2.balanceOf(beneficiary1);

        assertEq(balance_after - balance_before, 50 * T2);
    }
    function testBidTransfersFullToFirstPayee() {
        var (id, base) = newTwoWayTwoPayeeAuction();

        var balance_before = t2.balanceOf(beneficiary1);
        bidder1.doBid(base, 70 * T2);
        var balance_after = t2.balanceOf(beneficiary1);

        assertEq(balance_after - balance_before, 60 * T2);
    }
    function testBidTransfersPartialToSecondPayee() {
        var (id, base) = newTwoWayTwoPayeeAuction();

        var balance_before = t2.balanceOf(beneficiary2);
        bidder1.doBid(base, 70 * T2);
        var balance_after = t2.balanceOf(beneficiary2);

        assertEq(balance_after - balance_before, 10 * T2);
    }
    function testBidTransfersFullToSecondPayee() {
        var (id, base) = newTwoWayTwoPayeeAuction();

        var balance_before = t2.balanceOf(beneficiary2);
        bidder1.doBid(base, 100 * T2);
        var balance_after = t2.balanceOf(beneficiary2);

        assertEq(balance_after - balance_before, 40 * T2);
    }
    function testSplitBidsTransferPartialToFirstPayee() {
        var (id, base) = newTwoWayTwoPayeeAuction();

        var balance_before = t2.balanceOf(beneficiary1);
        var (nid, sid) = bidder1.doBid(base, 20 * T2, 40 * T1);
        bidder2.doBid(nid, 20 * T2, 50 * T1);
        var balance_after = t2.balanceOf(beneficiary1);

        assertEq(balance_after - balance_before, 40 * T2);
    }
    function testSplitBidsTransfersFullToFirstPayee() {
        var (id, base) = newTwoWayTwoPayeeAuction();

        var balance_before = t2.balanceOf(beneficiary1);
        var (nid, sid) = bidder1.doBid(base, 50 * T2, 40 * T1);
        bidder2.doBid(nid, 20 * T2, 50 * T1);
        var balance_after = t2.balanceOf(beneficiary1);

        assertEq(balance_after - balance_before, 60 * T2);
    }
    function testSplitBidsTransferPartialToSecondPayee() {
        var (id, base) = newTwoWayTwoPayeeAuction();

        var balance_before = t2.balanceOf(beneficiary2);
        var (nid, sid) = bidder1.doBid(base, 40 * T2, 40 * T1);
        bidder2.doBid(nid, 30 * T2, 50 * T1);
        var balance_after = t2.balanceOf(beneficiary2);

        assertEq(balance_after - balance_before, 10 * T2);
    }
    function testSplitBidsTransfersFullToSecondPayee() {
        var (id, base) = newTwoWayTwoPayeeAuction();

        var balance_before = t2.balanceOf(beneficiary2);
        var (nid, sid) = bidder1.doBid(base, 50 * T2, 40 * T1);
        bidder2.doBid(nid, 50 * T2, 50 * T1);
        var balance_after = t2.balanceOf(beneficiary2);

        assertEq(balance_after - balance_before, 40 * T2);
    }
    function testExcessBidTransfersFullyToFirstPayee() {
        var (id, base) = newTwoWayTwoPayeeAuction();

        var balance_before = t2.balanceOf(beneficiary1);
        bidder1.doBid(base, 200 * T2);
        var balance_after = t2.balanceOf(beneficiary1);

        assertEq(balance_after - balance_before, 60 * T2);
    }
    function testExcessBidTransfersFullyToSecondPayee() {
        var (id, base) = newTwoWayTwoPayeeAuction();

        var balance_before = t2.balanceOf(beneficiary2);
        bidder1.doBid(base, 200 * T2);
        var balance_after = t2.balanceOf(beneficiary2);

        assertEq(balance_after - balance_before, 40 * T2);
    }
}
