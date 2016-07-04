import 'tests/base.sol';
import 'db.sol';

contract DBTester is Tester {
    TestableManager _manager;
    function bindManager(address manager) {
        _manager = TestableManager(manager);
    }
}

contract CRUDTest is AuctionTest, AuctionDatabase {
    AuctionDatabase _db;

    function setUp() {
        _db = new AuctionDatabase();

        Auction memory auction;
        createAuction(auction);

        Auctionlet memory auctionlet;
        createAuctionlet(auctionlet);
    }
    function testReadOnlyAuction() {
        var A = readAuction(1);

        assertEq(_auctions[1].duration, 0);
        A.duration = 100 years;
        assertEq(_auctions[1].duration, 0);
    }
    function testReadOnlyAuctionlet() {
        var a = readAuctionlet(1);

        assertEq(_auctionlets[1].base, false);
        a.base = true;
        assertEq(_auctionlets[1].base, false);
    }
}

contract AuctionDBTest is AuctionTest {
    DBTester tester;

    function newAuction() returns (uint, uint) {
        return manager.newAuction( seller    // beneficiary
                                 , t1        // selling
                                 , t2        // buying
                                 , 100 * T1  // sell_amount
                                 , 10 * T2   // start_bid
                                 , 1 * T2    // min_increase
                                 , 1 years   // duration
                                 );
    }
    function testDefaultRefund() {
        var (id, base) = newAuction();

        assertEq(manager.getRefundAddress(id), seller);
    }
}
