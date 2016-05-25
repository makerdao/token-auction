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
        assertEq(last_bidder, manager);
        assertEq(buy_amount, 5 * T2);
        assertEq(sell_amount, 100 * T1);
    }
}
